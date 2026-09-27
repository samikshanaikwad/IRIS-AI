from __future__ import annotations

import csv
import json
import tempfile
import unittest
from pathlib import Path

from iris_dataset.dota import source_video_id
from iris_dataset.extraction import (
    NORMAL_WINDOW_FIELDS,
    VISIBLE_WINDOW_FIELDS,
    extract_dota_frames,
    load_category_policy,
    load_extraction_policy,
    load_normal_windows,
    load_visible_windows,
    select_spaced_frames,
)
from iris_dataset.image_tools import sha256_file
from iris_dataset.manifest import DatasetConfigurationError

from tests.support import create_image


def _approved_source():
    return {
        "dataset_id": "dota-official",
        "dataset_version": "test-dota-version",
        "usage_status": "APPROVED",
        "derived_data_status": "APPROVED",
    }


def _extraction_policy(status: str = "APPROVED"):
    return {
        "extraction_version": "test-dota-extraction-v1",
        "policy_status": status,
        "source_dataset_id": "dota-official",
        "source_frames_per_second": 10,
        "normal_pre_event_buffer_frames": 5,
        "normal_reviewed_window_required": True,
        "post_event_normal_enabled": False,
        "accident_visible_window_required": True,
        "minimum_temporal_spacing_frames": 5,
        "maximum_accident_frames_per_event": 2,
        "maximum_normal_frames_per_event": 2,
        "copy_mode": "BYTE_PRESERVING",
        "allowed_source_extensions": [".jpg", ".jpeg", ".png"],
    }


def _category_policy(status: str = "APPROVED"):
    return {
        "policy_version": "test-category-v1",
        "policy_status": status,
        "source_dataset_id": "dota-official",
        "categories": [
            {
                "annotation_id": 5,
                "annotation_name": "turning",
                "viewpoint": "ego",
                "iris_action": "INCLUDE_ACCIDENT",
            }
        ],
    }


class DotaExtractionTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.annotation_root = self.root / "annotations"
        self.source_root = self.root / "source"
        self.output_root = self.root / "derived"
        self.annotation_root.mkdir()
        self.event_id = "youtube123_000100"
        labels = []
        for frame_id in range(41):
            relative = Path("frames") / self.event_id / "images" / f"{frame_id:06d}.jpg"
            create_image(
                self.source_root / relative,
                color=(frame_id, (frame_id * 3) % 255, (frame_id * 7) % 255),
                image_format="JPEG",
            )
            labels.append(
                {
                    "frame_id": frame_id,
                    "image_path": relative.as_posix(),
                    "accident_id": 0 if frame_id < 20 else 5,
                    "accident_name": "normal" if frame_id < 20 else "turning",
                    "objects": [],
                }
            )
        annotation = {
            "video_name": self.event_id,
            "num_frames": 41,
            "ignore": False,
            "ego_involve": True,
            "night": False,
            "anomaly_start": 20,
            "anomaly_end": 35,
            "video_start": 100,
            "video_end": 140,
            "accident_id": "5",
            "accident_name": "turning",
            "labels": labels,
        }
        (self.annotation_root / f"{self.event_id}.json").write_text(
            json.dumps(annotation), encoding="utf-8"
        )
        self.visible_windows = {
            self.event_id: {
                "review_version": "test-review-v1",
                "source_event_id": self.event_id,
                "visible_start_frame": "25",
                "visible_end_frame": "35",
                "reviewer": "unit-test",
                "reviewed_at": "2026-01-01",
                "rationale": "Synthetic test fixture only",
            }
        }
        self.normal_windows = {
            self.event_id: {
                "review_version": "test-review-v1",
                "source_event_id": self.event_id,
                "normal_start_frame": "0",
                "normal_end_frame": "14",
                "reviewer": "unit-test",
                "reviewed_at": "2026-01-01",
                "rationale": "Synthetic test fixture only",
            }
        }

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_byte_preserving_extraction_and_manifest_values(self) -> None:
        result = extract_dota_frames(
            self.annotation_root,
            self.source_root,
            self.output_root,
            self.normal_windows,
            self.visible_windows,
            _category_policy(),
            _extraction_policy(),
            _approved_source(),
        )
        self.assertEqual(len(result.rows), 4)
        self.assertEqual({row["label"] for row in result.rows}, {"accident", "non_accident"})
        self.assertEqual({row["split"] for row in result.rows}, {""})
        self.assertEqual(
            {row["source_group_id"] for row in result.rows},
            {"dota-official:youtube123"},
        )
        for row in result.rows:
            destination = self.output_root / row["relative_path"]
            source = (
                self.source_root
                / "frames"
                / self.event_id
                / "images"
                / destination.name
            )
            self.assertEqual(destination.read_bytes(), source.read_bytes())
            self.assertEqual(row["sha256"], sha256_file(source))

    def test_missing_visible_window_skips_accident_frames_truthfully(self) -> None:
        result = extract_dota_frames(
            self.annotation_root,
            self.source_root,
            self.output_root,
            self.normal_windows,
            {},
            _category_policy(),
            _extraction_policy(),
            _approved_source(),
        )
        self.assertEqual({row["label"] for row in result.rows}, {"non_accident"})
        self.assertEqual(len(result.warnings), 1)

    def test_unapproved_source_blocks_extraction(self) -> None:
        source = _approved_source()
        source["usage_status"] = "REVIEW_REQUIRED"
        with self.assertRaises(DatasetConfigurationError):
            extract_dota_frames(
                self.annotation_root,
                self.source_root,
                self.output_root,
                self.normal_windows,
                self.visible_windows,
                _category_policy(),
                _extraction_policy(),
                source,
            )

    def test_officially_ignored_annotation_is_excluded(self) -> None:
        annotation_path = self.annotation_root / f"{self.event_id}.json"
        annotation = json.loads(annotation_path.read_text(encoding="utf-8"))
        annotation["ignore"] = True
        annotation_path.write_text(json.dumps(annotation), encoding="utf-8")
        result = extract_dota_frames(
            self.annotation_root,
            self.source_root,
            self.output_root,
            self.normal_windows,
            self.visible_windows,
            _category_policy(),
            _extraction_policy(),
            _approved_source(),
        )
        self.assertEqual(result.rows, ())
        self.assertTrue(
            any("official annotation is ignored" in item for item in result.warnings)
        )

    def test_unapproved_policies_block_extraction(self) -> None:
        with self.assertRaises(DatasetConfigurationError):
            extract_dota_frames(
                self.annotation_root,
                self.source_root,
                self.output_root,
                self.normal_windows,
                self.visible_windows,
                _category_policy(status="REVIEW_REQUIRED"),
                _extraction_policy(),
                _approved_source(),
            )
        with self.assertRaises(DatasetConfigurationError):
            extract_dota_frames(
                self.annotation_root,
                self.source_root,
                self.output_root,
                self.normal_windows,
                self.visible_windows,
                _category_policy(),
                _extraction_policy(status="REVIEW_REQUIRED"),
                _approved_source(),
            )

    def test_visible_window_must_be_inside_official_anomaly_window(self) -> None:
        windows = {self.event_id: dict(self.visible_windows[self.event_id])}
        windows[self.event_id]["visible_start_frame"] = "19"
        with self.assertRaises(DatasetConfigurationError):
            extract_dota_frames(
                self.annotation_root,
                self.source_root,
                self.output_root,
                self.normal_windows,
                windows,
                _category_policy(),
                _extraction_policy(),
                _approved_source(),
            )

    def test_frame_sampling_is_deterministic_and_spaced(self) -> None:
        candidates = list(range(30))
        first = select_spaced_frames(candidates, maximum_count=3, minimum_spacing=5)
        second = select_spaced_frames(candidates, maximum_count=3, minimum_spacing=5)
        self.assertEqual(first, second)
        self.assertEqual(len(first), 3)
        self.assertTrue(all(right - left >= 5 for left, right in zip(first, first[1:])))

    def test_source_video_id_preserves_embedded_underscore(self) -> None:
        self.assertEqual(source_video_id("abc_def_000123"), "abc_def")
        with self.assertRaises(DatasetConfigurationError):
            source_video_id("invalid")
        with self.assertRaises(DatasetConfigurationError):
            source_video_id("../unsafe_000123")

    def test_missing_reviewed_normal_window_skips_non_accident_frames(self) -> None:
        result = extract_dota_frames(
            self.annotation_root,
            self.source_root,
            self.output_root,
            {},
            self.visible_windows,
            _category_policy(),
            _extraction_policy(),
            _approved_source(),
        )
        self.assertEqual({row["label"] for row in result.rows}, {"accident"})
        self.assertTrue(
            any("no reviewed normal window" in warning for warning in result.warnings)
        )

    def test_reviewed_normal_window_must_precede_exclusion_buffer(self) -> None:
        windows = {self.event_id: dict(self.normal_windows[self.event_id])}
        windows[self.event_id]["normal_end_frame"] = "15"
        with self.assertRaises(DatasetConfigurationError):
            extract_dota_frames(
                self.annotation_root,
                self.source_root,
                self.output_root,
                windows,
                self.visible_windows,
                _category_policy(),
                _extraction_policy(),
                _approved_source(),
            )

    def test_visible_window_parser_requires_real_review_metadata(self) -> None:
        path = self.root / "visible.csv"
        with path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=VISIBLE_WINDOW_FIELDS)
            writer.writeheader()
            writer.writerow(self.visible_windows[self.event_id])
        loaded = load_visible_windows(path)
        self.assertEqual(loaded[self.event_id]["reviewer"], "unit-test")

    def test_normal_window_parser_requires_real_review_metadata(self) -> None:
        path = self.root / "normal.csv"
        with path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=NORMAL_WINDOW_FIELDS)
            writer.writeheader()
            writer.writerow(self.normal_windows[self.event_id])
        loaded = load_normal_windows(path)
        self.assertEqual(loaded[self.event_id]["reviewer"], "unit-test")

    def test_category_policy_rejects_duplicate_mapping(self) -> None:
        path = self.root / "categories.json"
        policy = _category_policy()
        policy["categories"].append(dict(policy["categories"][0]))
        path.write_text(json.dumps(policy), encoding="utf-8")
        with self.assertRaises(DatasetConfigurationError):
            load_category_policy(path)

    def test_extraction_policy_rejects_negative_buffer(self) -> None:
        path = self.root / "extraction.json"
        policy = _extraction_policy()
        policy["normal_pre_event_buffer_frames"] = -1
        path.write_text(json.dumps(policy), encoding="utf-8")
        with self.assertRaises(DatasetConfigurationError):
            load_extraction_policy(path)


if __name__ == "__main__":
    unittest.main()
