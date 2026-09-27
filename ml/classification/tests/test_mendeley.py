from __future__ import annotations

import csv
import hashlib
import io
import json
import tempfile
import unittest
import zipfile
from pathlib import Path

from PIL import Image

from iris_dataset.mendeley import (
    INSPECTION_VERSION,
    REVIEW_BATCH_FIELDS,
    REVIEW_FIELDS,
    REVIEW_VERSION,
    SourceInspectionError,
    apply_review_batch,
    apply_cross_source_leakage_groups,
    create_review_batch,
    inspect_accident_detection_archive,
    inspect_dats_archive,
    load_review_inventory,
    validate_review_inventory,
    write_review_inventory,
)


def _png_bytes(color: tuple[int, int, int], size: tuple[int, int]) -> bytes:
    output = io.BytesIO()
    Image.new("RGB", size, color).save(output, format="PNG")
    return output.getvalue()


class MendeleySourceInspectionTest(unittest.TestCase):
    def test_cross_source_duplicate_is_forced_into_one_leakage_group(self) -> None:
        shared = {
            **{field: "" for field in REVIEW_FIELDS},
            "sha256": "a" * 64,
            "perceptual_hash": "1234567890abcdef",
            "technical_status": "READABLE",
            "review_decision": "pending",
        }
        accident = [
            {
                **shared,
                "source_dataset_id": "accident-detection-9k-mendeley",
                "source_item": "accident.jpg",
                "source_group_id": "accident-detection-9k:group-a",
                "group_basis": "test-only",
            }
        ]
        dats = [
            {
                **shared,
                "source_dataset_id": "dats-2022-mendeley",
                "source_item": "normal-candidate.jpg",
                "source_group_id": "dats-2022:group-b",
                "group_basis": "test-only",
            }
        ]

        accident_result, dats_result, summary = apply_cross_source_leakage_groups(
            accident, dats
        )

        self.assertEqual(summary["exact_duplicate_pairs"], 1)
        self.assertEqual(summary["cross_source_leakage_groups"], 1)
        self.assertEqual(
            accident_result[0]["source_group_id"],
            dats_result[0]["source_group_id"],
        )
        self.assertTrue(
            accident_result[0]["source_group_id"].startswith("cross-source:")
        )

    def test_accident_archive_requires_pending_review_despite_valid_box(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            archive_path = root / "accident.zip"
            image = _png_bytes((20, 40, 60), (32, 24))
            with zipfile.ZipFile(archive_path, "w") as archive:
                archive.writestr(
                    "Accident_Detection/Dataset/train/images/source_png.rf.abc.jpg",
                    image,
                )
                archive.writestr(
                    "Accident_Detection/Dataset/train/labels/source_png.rf.abc.txt",
                    "0 0.5 0.5 0.4 0.4\n",
                )

            summary, rows = inspect_accident_detection_archive(archive_path)

            self.assertEqual(summary["image_files"], 1)
            self.assertEqual(summary["readable_images"], 1)
            self.assertEqual(summary["publisher_annotated_technical_candidates"], 1)
            self.assertEqual(summary["semantically_reviewed_accident_images"], 0)
            self.assertEqual(summary["rights_approved_accident_images"], 0)
            self.assertEqual(rows[0]["annotation_status"], "VALID_ACCIDENT_ANNOTATION")
            self.assertEqual(rows[0]["review_decision"], "pending")
            self.assertEqual(rows[0]["label_basis"], "")
            self.assertEqual(rows[0]["rights_status"], "REVIEW_REQUIRED")

    def test_invalid_accident_annotation_is_not_a_technical_candidate(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            archive_path = root / "accident.zip"
            with zipfile.ZipFile(archive_path, "w") as archive:
                archive.writestr(
                    "Accident_Detection/Dataset/test/images/source.jpg",
                    _png_bytes((1, 2, 3), (8, 8)),
                )
                archive.writestr(
                    "Accident_Detection/Dataset/test/labels/source.txt",
                    "1 0.5 0.5 0.4 0.4\n",
                )

            summary, rows = inspect_accident_detection_archive(archive_path)

            self.assertEqual(summary["publisher_annotated_technical_candidates"], 0)
            self.assertEqual(
                rows[0]["annotation_status"], "INVALID_YOLO_ACCIDENT_CLASS"
            )

            rows[0].update(
                {
                    "review_decision": "accident",
                    "label_basis": "Test-only visual review decision.",
                    "reviewer": "test-reviewer",
                    "review_date": "2026-09-27",
                }
            )
            review_path = root / "review.csv"
            write_review_inventory(review_path, rows)
            validation = validate_review_inventory(review_path)
            self.assertTrue(
                any(
                    "requires a valid publisher Accident annotation" in error
                    for error in validation["validation_errors"]
                )
            )

    def test_dats_archive_is_verified_but_remains_unlabelled(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            archive_path = root / "dats.zip"
            inventory_root = root / "inventory"
            inventory_root.mkdir()
            image = _png_bytes((80, 100, 120), (20, 10))
            annotation = json.dumps(
                [
                    {
                        "image": "1634016299438.png",
                        "annotations": [
                            {"label": "Car", "coordinates": {"x": 1, "y": 1}}
                        ],
                    }
                ]
            ).encode("utf-8")
            with zipfile.ZipFile(archive_path, "w") as archive:
                archive.writestr(
                    "Images with Annotations/Images/1634016299438.png", image
                )
                archive.writestr(
                    "Images with Annotations/JSON files/1634016299438.json",
                    annotation,
                )

            records = [
                {
                    "filename": "1634016299438.png",
                    "id": "image-id",
                    "size": len(image),
                    "content_details": {
                        "sha256_hash": hashlib.sha256(image).hexdigest()
                    },
                },
                {
                    "filename": "1634016299438.json",
                    "id": "annotation-id",
                    "size": len(annotation),
                    "content_details": {
                        "sha256_hash": hashlib.sha256(annotation).hexdigest()
                    },
                },
            ]
            (inventory_root / "source.page0000.json").write_text(
                json.dumps(records), encoding="utf-8"
            )

            summary, rows = inspect_dats_archive(archive_path, inventory_root)

            self.assertTrue(summary["archive_content_matches_inventory_hash_multiset"])
            self.assertEqual(
                summary["candidate_normal_images_pending_semantic_review"], 1
            )
            self.assertEqual(summary["semantically_reviewed_non_accident_images"], 0)
            self.assertEqual(summary["duplicate_analysis"]["source_groups"], 1)
            self.assertEqual(
                summary["object_detection_class_names_by_format"][".json"], ["Car"]
            )
            self.assertEqual(rows[0]["review_decision"], "pending")
            self.assertEqual(rows[0]["label_basis"], "")
            self.assertEqual(rows[0]["rights_status"], "APPROVED")
            self.assertTrue(rows[0]["source_group_id"].startswith("dats-2022:"))
            self.assertIn("epoch_millisecond", rows[0]["group_basis"])

    def test_review_inventory_round_trip_preserves_empty_label(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "review.csv"
            row = {field: "" for field in REVIEW_FIELDS}
            row["review_version"] = REVIEW_VERSION
            row["inspection_tool_version"] = INSPECTION_VERSION
            row["review_decision"] = "pending"

            write_review_inventory(path, [row])
            loaded = load_review_inventory(path)

            self.assertEqual(loaded[0]["review_decision"], "pending")
            self.assertEqual(loaded[0]["label_basis"], "")

    def test_dats_review_batch_requires_explicit_persisted_decision(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            archive_path = root / "dats.zip"
            inventory_path = root / "review.csv"
            batch_root = root / "batch"
            image = _png_bytes((100, 120, 140), (12, 8))
            member_name = "Images with Annotations/Images/1634016299438.png"
            with zipfile.ZipFile(archive_path, "w") as archive:
                archive.writestr(member_name, image)
            digest = hashlib.sha256(image).hexdigest()
            rows = [
                {
                    **{field: "" for field in REVIEW_FIELDS},
                    "review_version": REVIEW_VERSION,
                    "inspection_tool_version": INSPECTION_VERSION,
                    "source_dataset_id": "dats-2022-mendeley",
                    "source_dataset_version": "test-v2",
                    "source_item": member_name,
                    "source_filename": "1634016299438.png",
                    "source_group_id": "dats-2022:timestamp-day-test",
                    "group_basis": "test-only",
                    "annotation_status": "OBJECT_DETECTION_ONLY_NOT_ACCIDENT_LABEL",
                    "technical_status": "READABLE",
                    "rights_status": "APPROVED",
                    "sha256": digest,
                    "perceptual_hash": "0000000000000000",
                    "width": "12",
                    "height": "8",
                    "decoded_format": "PNG",
                    "review_decision": "pending",
                }
            ]
            write_review_inventory(inventory_path, rows)

            result = create_review_batch(
                archive_path,
                inventory_path,
                batch_root,
                "dats-2022-mendeley",
                start=0,
                limit=1,
            )
            self.assertEqual(result["batch_items"], 1)
            self.assertEqual(
                validate_review_inventory(inventory_path)["decision_counts"],
                {"pending": 1},
            )

            batch_path = batch_root / "review_batch.csv"
            with batch_path.open("r", encoding="utf-8", newline="") as handle:
                batch_rows = list(csv.DictReader(handle))
            batch_rows[0].update(
                {
                    "review_decision": "non_accident",
                    "label_basis": (
                        "Human review found a road scene without visible accident "
                        "evidence."
                    ),
                    "reviewer": "test-reviewer",
                    "review_date": "2026-09-27",
                }
            )
            with batch_path.open("w", encoding="utf-8", newline="") as handle:
                writer = csv.DictWriter(
                    handle, fieldnames=REVIEW_BATCH_FIELDS, lineterminator="\n"
                )
                writer.writeheader()
                writer.writerows(batch_rows)

            applied = apply_review_batch(inventory_path, batch_path)
            loaded = load_review_inventory(inventory_path)
            self.assertEqual(applied["applied_decisions"], 1)
            self.assertEqual(applied["accepted_items_with_approved_rights"], 1)
            self.assertEqual(loaded[0]["review_decision"], "non_accident")
            self.assertIn("without visible accident", loaded[0]["label_basis"])

            batch_rows[0]["sha256"] = "0" * 64
            with batch_path.open("w", encoding="utf-8", newline="") as handle:
                writer = csv.DictWriter(
                    handle, fieldnames=REVIEW_BATCH_FIELDS, lineterminator="\n"
                )
                writer.writeheader()
                writer.writerows(batch_rows)
            with self.assertRaisesRegex(
                SourceInspectionError, "hash no longer matches"
            ):
                apply_review_batch(inventory_path, batch_path)

    def test_review_batch_rejects_archive_hash_drift(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            archive_path = root / "source.zip"
            inventory_path = root / "review.csv"
            member_name = "Images/source.png"
            with zipfile.ZipFile(archive_path, "w") as archive:
                archive.writestr(member_name, _png_bytes((1, 2, 3), (8, 8)))
            row = {field: "" for field in REVIEW_FIELDS}
            row.update(
                {
                    "review_version": REVIEW_VERSION,
                    "inspection_tool_version": INSPECTION_VERSION,
                    "source_dataset_id": "dats-2022-mendeley",
                    "source_item": member_name,
                    "source_filename": "source.png",
                    "technical_status": "READABLE",
                    "sha256": "0" * 64,
                    "review_decision": "pending",
                }
            )
            write_review_inventory(inventory_path, [row])

            with self.assertRaisesRegex(
                SourceInspectionError, "hash no longer matches"
            ):
                create_review_batch(
                    archive_path,
                    inventory_path,
                    root / "batch",
                    "dats-2022-mendeley",
                    start=0,
                    limit=1,
                )


if __name__ == "__main__":
    unittest.main()
