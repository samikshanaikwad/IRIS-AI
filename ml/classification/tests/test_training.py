from __future__ import annotations

import copy
import tempfile
import unittest
from pathlib import Path

from PIL import Image

from iris_dataset.training import (
    PreprocessConfig,
    TrainingBlockedError,
    binary_metrics,
    preprocess_image,
    preflight_manifest,
    select_validation_threshold,
    validate_training_rows,
)
from tests.support import create_image, manifest_row, write_registry, write_rows


class TrainingPipelineTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.data_root = self.root / "derived"
        self.data_root.mkdir()
        self.manifest = self.root / "manifest.csv"
        self.registry = self.root / "registry.json"
        write_registry(self.registry)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_production_preflight_refuses_missing_accident_class(self) -> None:
        write_rows(self.manifest, [])
        result = preflight_manifest(self.manifest, self.data_root, self.registry)
        self.assertEqual(result["status"], "BLOCKED")
        self.assertFalse(result["training_allowed"])
        self.assertIn("APPROVED_ACCIDENT_SAMPLES_MISSING", result["errors"])
        self.assertIn("no rights-cleared accident-positive", result["message"])

    def test_group_and_exact_duplicate_leakage_are_hard_errors(self) -> None:
        create_image(self.data_root / "a.png")
        first = manifest_row(self.data_root, "a.png", item_id="a", split="train", group_id="g1")
        second = copy.deepcopy(first)
        second["item_id"] = "b"
        second["relative_path"] = "a.png"
        second["split"] = "test"
        errors = validate_training_rows([first, second], self.data_root, require_all_classes_in_each_split=False)
        self.assertTrue(any(error.startswith("SOURCE_GROUP_CROSSES_SPLITS") for error in errors))
        self.assertTrue(any(error.startswith("CROSS_SPLIT_EXACT_DUPLICATE") for error in errors))

    def test_missing_group_and_unapproved_rights_are_rejected(self) -> None:
        create_image(self.data_root / "a.png")
        row = manifest_row(self.data_root, "a.png", group_id="", license_status="REVIEW_REQUIRED")
        errors = validate_training_rows([row], self.data_root, require_all_classes_in_each_split=False)
        self.assertIn("MISSING_SOURCE_GROUP_ID:item-1", errors)
        self.assertIn("ITEM_RIGHTS_NOT_APPROVED:item-1", errors)

    def test_threshold_uses_validation_scores_and_is_deterministic(self) -> None:
        labels = [0, 0, 1, 1]
        scores = [0.1, 0.4, 0.6, 0.9]
        first = select_validation_threshold(labels, scores)
        second = select_validation_threshold(labels, scores)
        self.assertEqual(first, second)
        self.assertEqual(first["source_split"], "validation")
        self.assertEqual(first["score_name"], "model score")
        self.assertNotIn("confidence", first)

    def test_metrics_are_real_counts(self) -> None:
        result = binary_metrics([0, 0, 1, 1], [0, 1, 1, 0])
        self.assertEqual(result["true_positive"], 1)
        self.assertEqual(result["true_negative"], 1)
        self.assertEqual(result["false_positive"], 1)
        self.assertEqual(result["false_negative"], 1)
        self.assertEqual(result["f1"], 0.5)

    def test_preprocessing_preserves_aspect_with_deterministic_letterbox(self) -> None:
        path = self.root / "wide.png"
        Image.new("RGB", (40, 20), (255, 0, 0)).save(path)
        config = PreprocessConfig(input_width=20, input_height=20)
        first = preprocess_image(path, config)
        second = preprocess_image(path, config)
        self.assertEqual(first.size, (20, 20))
        self.assertEqual(first.tobytes(), second.tobytes())
        self.assertEqual(first.getpixel((0, 0)), (0, 0, 0))
        self.assertEqual(first.getpixel((10, 10)), (255, 0, 0))

    def test_invalid_threshold_inputs_are_rejected(self) -> None:
        with self.assertRaises(TrainingBlockedError):
            select_validation_threshold([1, 1], [0.4, 0.8])


if __name__ == "__main__":
    unittest.main()
