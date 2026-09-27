from __future__ import annotations

import json
import unittest
from collections import Counter
from pathlib import Path

from iris_dataset.extraction import load_category_policy, load_extraction_policy
from iris_dataset.manifest import load_source_registry
from iris_dataset.splitting import load_split_policy

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
CONFIG_ROOT = REPOSITORY_ROOT / "ml/classification/configs"
MANIFEST_ROOT = REPOSITORY_ROOT / "datasets/manifests/classification"


class VersionControlledConfigurationTest(unittest.TestCase):
    def test_dota_source_is_not_approved_without_content_terms(self) -> None:
        registry = load_source_registry(MANIFEST_ROOT / "source_registry.v1.json")
        source = registry["dota-official"]
        self.assertEqual(source["code_license"], "MIT")
        self.assertIsNone(source["dataset_content_license"])
        self.assertEqual(source["usage_status"], "REVIEW_REQUIRED")
        self.assertEqual(source["derived_data_status"], "REVIEW_REQUIRED")

    def test_mendeley_sources_record_rights_and_semantic_limits(self) -> None:
        registry = load_source_registry(MANIFEST_ROOT / "source_registry.v1.json")
        accident = registry["accident-detection-9k-mendeley"]
        dats = registry["dats-2022-mendeley"]

        self.assertEqual(accident["doi"], "10.17632/4x5my8gbcs.2")
        self.assertEqual(
            accident["dataset_content_license"].split()[0:3],
            ["CC", "BY", "4.0"],
        )
        self.assertEqual(accident["usage_status"], "REVIEW_REQUIRED")
        self.assertTrue(
            any("Google image searches" in note for note in accident["notes"])
        )
        self.assertFalse(accident["interactive_authentication_required"])

        self.assertEqual(dats["doi"], "10.17632/nfc34n8svj.2")
        self.assertEqual(dats["dataset_content_license"], "CC BY 4.0")
        self.assertEqual(dats["usage_status"], "APPROVED")
        self.assertIsNotNone(dats["data_acquired_at"])
        self.assertEqual(
            dats["downloaded_artifact_checksums"]["DATS_2022.zip"],
            "f4ffe186ea9d9c72e2f141e76c285b6b8740b0f4de672e58330b8a80ae36629f",
        )
        self.assertTrue(
            any("no image is automatically" in note for note in dats["notes"])
        )
        self.assertEqual(
            sum(item["file_count"] for item in dats["public_file_inventory"]),
            10245,
        )
        self.assertEqual(
            sum(item["total_bytes"] for item in dats["public_file_inventory"]),
            10737310801,
        )

    def test_dota_category_policy_covers_observed_id_viewpoint_pairs(self) -> None:
        policy = load_category_policy(CONFIG_ROOT / "dota_category_policy.v1.json")
        categories = policy["categories"]
        keys = {
            (category["annotation_id"], category["viewpoint"])
            for category in categories
        }
        self.assertEqual(len(categories), 20)
        expected_keys = {
            (identifier, view)
            for identifier in range(1, 11)
            for view in ("ego", "other")
        }
        self.assertEqual(keys, expected_keys)
        self.assertEqual(
            Counter(category["iris_action"] for category in categories),
            Counter(
                {
                    "INCLUDE_ACCIDENT": 14,
                    "EXCLUDE_AMBIGUOUS": 4,
                    "REVIEW_REQUIRED": 2,
                }
            ),
        )
        self.assertEqual(policy["policy_status"], "REVIEW_REQUIRED")
        self.assertEqual(
            policy["normal_precursor_action"], "POSSIBLE_NON_ACCIDENT_SOURCE"
        )

    def test_extraction_policy_requires_both_human_review_windows(self) -> None:
        policy = load_extraction_policy(CONFIG_ROOT / "extraction_policy.v1.json")
        self.assertEqual(policy["policy_status"], "REVIEW_REQUIRED")
        self.assertEqual(policy["source_frames_per_second"], 10)
        self.assertEqual(policy["normal_pre_event_buffer_frames"], 20)
        self.assertTrue(policy["normal_reviewed_window_required"])
        self.assertTrue(policy["accident_visible_window_required"])
        self.assertFalse(policy["post_event_normal_enabled"])
        self.assertEqual(policy["minimum_temporal_spacing_frames"], 10)
        self.assertEqual(policy["maximum_accident_frames_per_event"], 3)
        self.assertEqual(policy["maximum_normal_frames_per_event"], 3)

    def test_split_policy_is_versioned_and_source_group_based(self) -> None:
        policy = load_split_policy(CONFIG_ROOT / "split_policy.v1.json")
        self.assertEqual(policy["seed"], 6006)
        self.assertEqual(policy["group_field"], "source_group_id")
        self.assertEqual(
            policy["targets"], {"train": 0.70, "validation": 0.15, "test": 0.15}
        )
        self.assertTrue(policy["preserve_external_test"])

    def test_mendeley_review_policy_never_auto_labels_candidates(self) -> None:
        policy = json.loads(
            (CONFIG_ROOT / "mendeley_review_policy.v1.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertFalse(policy["dats_2022"]["automatic_non_accident_labelling"])
        self.assertTrue(
            policy["accident_detection_9k"]["human_semantic_review_required"]
        )
        self.assertTrue(
            policy["accident_detection_9k"][
                "underlying_image_rights_approval_required"
            ]
        )
        self.assertFalse(
            policy["manifest_gate"]["pending_review_rows_are_manifest_eligible"]
        )
        self.assertEqual(
            policy["duplicate_policy"]["near_duplicate_hamming_threshold"], 4
        )


if __name__ == "__main__":
    unittest.main()
