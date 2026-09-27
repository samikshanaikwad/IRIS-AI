from __future__ import annotations

import shutil
import tempfile
import unittest
from pathlib import Path

from iris_dataset.image_tools import sha256_file
from iris_dataset.manifest import DatasetConfigurationError
from iris_dataset.validation import validate_dataset

from tests.support import (
    EXTRACTION_VERSION,
    create_image,
    manifest_row,
    write_registry,
    write_rows,
)


class DatasetValidationTest(unittest.TestCase):
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

    def validate(self):
        return validate_dataset(
            self.manifest,
            self.registry,
            self.data_root,
            {EXTRACTION_VERSION},
        )

    def row(self, name: str = "one.png", **overrides):
        create_image(self.data_root / name)
        row = manifest_row(self.data_root, name, **overrides)
        return row

    def assert_has_code(self, result, code: str) -> None:
        self.assertIn(code, {issue.code for issue in result.issues})

    def test_empty_manifest_is_valid_but_not_training_eligible(self) -> None:
        write_rows(self.manifest, [])
        result = self.validate()
        self.assertEqual(result.error_count, 0)
        self.assertFalse(result.training_eligible)
        self.assert_has_code(result, "EMPTY_DATASET")

    def test_valid_real_bytes_pass(self) -> None:
        write_rows(self.manifest, [self.row()])
        result = self.validate()
        self.assertEqual(result.error_count, 0)
        self.assertTrue(result.training_eligible)

    def test_rejects_invalid_label_and_split(self) -> None:
        row = self.row()
        row["label"] = "unknown"
        row["split"] = "demo"
        write_rows(self.manifest, [row])
        result = self.validate()
        self.assert_has_code(result, "INVALID_LABEL")
        self.assert_has_code(result, "INVALID_SPLIT")

    def test_rejects_duplicate_item_id_and_path(self) -> None:
        first = self.row(item_id="duplicate")
        second = dict(first)
        second["source_group_id"] = "group-2"
        second["source_event_id"] = "event-2"
        write_rows(self.manifest, [first, second])
        result = self.validate()
        self.assert_has_code(result, "DUPLICATE_ITEM_ID")
        self.assert_has_code(result, "DUPLICATE_RELATIVE_PATH")

    def test_rejects_hash_mismatch_without_changing_stored_hash(self) -> None:
        row = self.row()
        original_hash = row["sha256"]
        create_image(self.data_root / "one.png", color=(200, 10, 5))
        write_rows(self.manifest, [row])
        result = self.validate()
        self.assert_has_code(result, "HASH_MISMATCH")
        self.assertEqual(row["sha256"], original_hash)

    def test_rejects_exact_duplicate_content_across_splits(self) -> None:
        first = self.row("one.png", item_id="one", split="train")
        shutil.copyfile(self.data_root / "one.png", self.data_root / "two.png")
        second = manifest_row(
            self.data_root,
            "two.png",
            item_id="two",
            split="test",
            group_id="group-2",
            event_id="event-2",
            video_id="video-2",
        )
        write_rows(self.manifest, [first, second])
        result = self.validate()
        self.assert_has_code(result, "CROSS_SPLIT_EXACT_DUPLICATE")

    def test_rejects_source_group_leakage(self) -> None:
        first = self.row("one.png", item_id="one", split="train")
        create_image(self.data_root / "two.png", color=(150, 70, 20))
        second = manifest_row(
            self.data_root,
            "two.png",
            item_id="two",
            split="validation",
            group_id=first["source_group_id"],
            event_id="event-2",
        )
        write_rows(self.manifest, [first, second])
        self.assert_has_code(self.validate(), "SOURCE_GROUP_LEAKAGE")

    def test_rejects_missing_source_registry_entry(self) -> None:
        row = self.row(source_id="unregistered")
        write_rows(self.manifest, [row])
        self.assert_has_code(self.validate(), "MISSING_SOURCE_REGISTRY")

    def test_rejects_unapproved_source_and_item_usage(self) -> None:
        write_registry(self.registry, approved=False)
        row = self.row(license_status="REVIEW_REQUIRED")
        write_rows(self.manifest, [row])
        result = self.validate()
        self.assert_has_code(result, "ITEM_USAGE_NOT_APPROVED")
        self.assert_has_code(result, "SOURCE_USAGE_NOT_APPROVED")
        self.assert_has_code(result, "DERIVED_USE_NOT_APPROVED")

    def test_rejects_missing_file(self) -> None:
        row = self.row()
        (self.data_root / "one.png").unlink()
        write_rows(self.manifest, [row])
        self.assert_has_code(self.validate(), "MISSING_FILE")

    def test_rejects_zero_byte_file(self) -> None:
        path = self.data_root / "empty.png"
        path.write_bytes(b"")
        row = self.row()
        row["relative_path"] = "empty.png"
        row["sha256"] = sha256_file(path)
        write_rows(self.manifest, [row])
        self.assert_has_code(self.validate(), "ZERO_BYTE_FILE")

    def test_rejects_corrupt_image(self) -> None:
        path = self.data_root / "corrupt.png"
        path.write_bytes(b"not an image")
        row = self.row()
        row["relative_path"] = "corrupt.png"
        row["sha256"] = sha256_file(path)
        write_rows(self.manifest, [row])
        self.assert_has_code(self.validate(), "IMAGE_DECODE_FAILURE")

    def test_rejects_unsupported_extension(self) -> None:
        path = self.data_root / "image.bmp"
        create_image(path, image_format="BMP")
        row = self.row()
        row["relative_path"] = "image.bmp"
        row["sha256"] = sha256_file(path)
        write_rows(self.manifest, [row])
        self.assert_has_code(self.validate(), "UNSUPPORTED_IMAGE_EXTENSION")

    def test_rejects_dimension_mismatch(self) -> None:
        row = self.row()
        row["width"] = "999"
        write_rows(self.manifest, [row])
        self.assert_has_code(self.validate(), "DIMENSION_MISMATCH")

    def test_rejects_unknown_extraction_version(self) -> None:
        row = self.row(extraction_version="unknown-version")
        write_rows(self.manifest, [row])
        self.assert_has_code(self.validate(), "UNKNOWN_EXTRACTION_VERSION")

    def test_rejects_source_version_mismatch(self) -> None:
        row = self.row(source_version="different-source-version")
        write_rows(self.manifest, [row])
        self.assert_has_code(self.validate(), "SOURCE_VERSION_MISMATCH")

    def test_rejects_relative_path_escape(self) -> None:
        row = self.row()
        row["relative_path"] = "../outside.png"
        write_rows(self.manifest, [row])
        self.assert_has_code(self.validate(), "UNSAFE_PATH")

    def test_rejects_manifest_header_mismatch(self) -> None:
        self.manifest.write_text("item_id,label\nitem-1,accident\n", encoding="utf-8")
        with self.assertRaises(DatasetConfigurationError):
            self.validate()

    def test_rejects_malformed_video_frame_index(self) -> None:
        row = self.row()
        row["source_frame_index"] = "not-an-integer"
        write_rows(self.manifest, [row])
        self.assert_has_code(self.validate(), "MALFORMED_INTEGER")

    def test_flags_near_duplicate_across_splits(self) -> None:
        first = self.row("dark.png", item_id="dark", split="train")
        create_image(self.data_root / "light.png", color=(220, 220, 220))
        second = manifest_row(
            self.data_root,
            "light.png",
            item_id="light",
            split="test",
            group_id="group-2",
            event_id="event-2",
            video_id="video-2",
        )
        write_rows(self.manifest, [first, second])
        self.assert_has_code(self.validate(), "CROSS_SPLIT_NEAR_DUPLICATE")


if __name__ == "__main__":
    unittest.main()
