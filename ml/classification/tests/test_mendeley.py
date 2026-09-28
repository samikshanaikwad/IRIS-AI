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
    validate_review_batch,
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
            contact_sheet = batch_root / "review_sheet.html"
            self.assertTrue(contact_sheet.is_file())
            self.assertIn(member_name, contact_sheet.read_text(encoding="utf-8"))
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

    def test_review_batch_explicitly_propagates_safe_exact_duplicates(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            archive_path = root / "dats.zip"
            inventory_path = root / "review.csv"
            batch_root = root / "batch"
            image = _png_bytes((100, 120, 140), (12, 8))
            first_item = "Images/first.png"
            second_item = "Images/second.png"
            with zipfile.ZipFile(archive_path, "w") as archive:
                archive.writestr(first_item, image)
                archive.writestr(second_item, image)
            digest = hashlib.sha256(image).hexdigest()
            rows = []
            for source_item in (first_item, second_item):
                rows.append(
                    {
                        **{field: "" for field in REVIEW_FIELDS},
                        "review_version": REVIEW_VERSION,
                        "inspection_tool_version": INSPECTION_VERSION,
                        "source_dataset_id": "dats-2022-mendeley",
                        "source_dataset_version": "test-v2",
                        "source_item": source_item,
                        "source_filename": Path(source_item).name,
                        "source_group_id": "dats-2022:safe-duplicate-group",
                        "group_basis": "test-only-exact-duplicate",
                        "annotation_status": (
                            "OBJECT_DETECTION_ONLY_NOT_ACCIDENT_LABEL"
                        ),
                        "technical_status": "READABLE",
                        "rights_status": "APPROVED",
                        "sha256": digest,
                        "perceptual_hash": "0000000000000000",
                        "width": "12",
                        "height": "8",
                        "decoded_format": "PNG",
                        "review_decision": "pending",
                    }
                )
            write_review_inventory(inventory_path, rows)

            result = create_review_batch(
                archive_path,
                inventory_path,
                batch_root,
                "dats-2022-mendeley",
                start=0,
                limit=100,
            )
            self.assertEqual(result["available_pending_rows"], 2)
            self.assertEqual(result["available_pending_unique_content_rows"], 1)
            self.assertEqual(result["batch_items"], 1)
            self.assertIn(
                "Exact-byte duplicates in DATS inventory: <code>2</code>",
                (batch_root / "review_sheet.html").read_text(encoding="utf-8"),
            )

            batch_path = batch_root / "review_batch.csv"
            with batch_path.open("r", encoding="utf-8", newline="") as handle:
                batch_rows = list(csv.DictReader(handle))
            batch_rows[0].update(
                {
                    "review_decision": "non_accident",
                    "label_basis": "Human visual review found no accident evidence.",
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

            applied = apply_review_batch(
                inventory_path, batch_path, propagate_exact_duplicates=True
            )
            loaded = load_review_inventory(inventory_path)
            self.assertEqual(applied["applied_decisions"], 1)
            self.assertEqual(applied["propagated_exact_duplicate_decisions"], 1)
            self.assertEqual(
                [row["review_decision"] for row in loaded],
                ["non_accident", "non_accident"],
            )
            self.assertIn(
                "Exact SHA-256 duplicate decision propagated",
                loaded[1]["rationale"],
            )

    def test_accident_positive_review_batch_stays_pending_and_uses_positive_policy(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            archive_path = root / "accident.zip"
            inventory_path = root / "accident-review.csv"
            batch_root = root / "batch"
            image = _png_bytes((120, 80, 40), (24, 16))
            member_name = "Accident_Detection/Dataset/train/images/source.jpg"
            label_name = "Accident_Detection/Dataset/train/labels/source.txt"
            with zipfile.ZipFile(archive_path, "w") as archive:
                archive.writestr(member_name, image)
                archive.writestr(label_name, "0 0.5 0.5 0.4 0.4\n")

            _, rows = inspect_accident_detection_archive(archive_path)
            write_review_inventory(inventory_path, rows)
            result = create_review_batch(
                archive_path,
                inventory_path,
                batch_root,
                "accident-detection-9k-mendeley",
                start=0,
                limit=100,
            )

            self.assertEqual(result["batch_items"], 1)
            batch_validation = validate_review_batch(
                archive_path, inventory_path, batch_root / "review_batch.csv", batch_root
            )
            self.assertEqual(batch_validation["validation_errors"], [])
            with (batch_root / "review_batch.csv").open(
                "r", encoding="utf-8", newline=""
            ) as handle:
                batch_rows = list(csv.DictReader(handle))
            self.assertEqual(batch_rows[0]["review_decision"], "pending")
            self.assertEqual(batch_rows[0]["label_basis"], "")
            sheet = (batch_root / "review_sheet.html").read_text(encoding="utf-8")
            self.assertIn("AccidentDetection-9k positive-candidate", sheet)
            self.assertIn("valid Accident annotation", sheet)
            self.assertIn("Decision: pending", sheet)

    def test_positive_batch_excludes_empty_missing_and_orphan_annotations(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            archive_path = root / "accident.zip"
            inventory_path = root / "accident-review.csv"
            batch_root = root / "batch"
            image = _png_bytes((30, 60, 90), (16, 12))
            members = [
                "Accident_Detection/Dataset/train/images/valid.jpg",
                "Accident_Detection/Dataset/train/images/empty.jpg",
                "Accident_Detection/Dataset/train/images/missing.jpg",
                "Accident_Detection/Dataset/train/images/orphan.jpg",
            ]
            with zipfile.ZipFile(archive_path, "w") as archive:
                for member in members:
                    archive.writestr(member, image + member.encode("utf-8"))
                archive.writestr(
                    "Accident_Detection/Dataset/train/labels/valid.txt",
                    "0 0.5 0.5 0.4 0.4\n",
                )
                archive.writestr(
                    "Accident_Detection/Dataset/train/labels/empty.txt", "\n"
                )
                archive.writestr(
                    "Accident_Detection/Dataset/train/labels/orphan.txt",
                    "0 0.5 0.5 0.4 0.4\n",
                )

            _, rows = inspect_accident_detection_archive(archive_path)
            orphan_row = next(row for row in rows if row["source_item"].endswith("orphan.jpg"))
            orphan_row["annotation_status"] = "ORPHAN"
            write_review_inventory(inventory_path, rows)

            result = create_review_batch(
                archive_path,
                inventory_path,
                batch_root,
                "accident-detection-9k-mendeley",
                start=0,
                limit=100,
            )

            self.assertEqual(result["batch_items"], 1)
            with (batch_root / "review_batch.csv").open(
                "r", encoding="utf-8", newline=""
            ) as handle:
                batch_rows = list(csv.DictReader(handle))
            self.assertTrue(batch_rows[0]["source_item"].endswith("valid.jpg"))
            self.assertEqual(batch_rows[0]["review_decision"], "pending")

    def test_positive_batch_selection_is_deterministic_and_excludes_prior_group(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            archive_path = root / "accident.zip"
            inventory_path = root / "accident-review.csv"
            first_root = root / "first"
            second_root = root / "second"
            members = [
                f"Accident_Detection/Dataset/train/images/source-{index}.jpg"
                for index in range(3)
            ]
            with zipfile.ZipFile(archive_path, "w") as archive:
                for index, member in enumerate(members):
                    fixture = Image.new("RGB", (64, 64), (20, 40, 60))
                    for x in range(64):
                        for y in range(64):
                            if (x * 13 + y * 7 + index * 53) % 101 < 50:
                                fixture.putpixel((x, y), (220, 180, 40))
                    encoded = io.BytesIO()
                    fixture.save(encoded, format="PNG")
                    archive.writestr(member, encoded.getvalue())
                    archive.writestr(
                        member.replace("/images/", "/labels/").replace(
                            ".jpg", ".txt"
                        ),
                        "0 0.5 0.5 0.4 0.4\n",
                    )

            _, rows = inspect_accident_detection_archive(archive_path)
            write_review_inventory(inventory_path, rows)
            first = create_review_batch(
                archive_path,
                inventory_path,
                first_root,
                "accident-detection-9k-mendeley",
                start=0,
                limit=1,
            )
            with (first_root / "review_batch.csv").open(
                "r", encoding="utf-8", newline=""
            ) as handle:
                first_row = next(csv.DictReader(handle))
            inventory_by_item = {row["source_item"]: row for row in rows}
            selected = inventory_by_item[first_row["source_item"]]
            second = create_review_batch(
                archive_path,
                inventory_path,
                second_root,
                "accident-detection-9k-mendeley",
                start=0,
                limit=1,
                excluded_source_items={first_row["source_item"]},
                excluded_hashes={first_row["sha256"]},
                excluded_source_groups={selected["source_group_id"]},
            )
            with (second_root / "review_batch.csv").open(
                "r", encoding="utf-8", newline=""
            ) as handle:
                second_row = next(csv.DictReader(handle))
            self.assertEqual(first["batch_items"], 1)
            self.assertEqual(second["batch_items"], 1)
            self.assertNotEqual(first_row["source_item"], second_row["source_item"])
            self.assertNotEqual(first_row["sha256"], second_row["sha256"])
            self.assertEqual(second_row["review_decision"], "pending")


if __name__ == "__main__":
    unittest.main()
