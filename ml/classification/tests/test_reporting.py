from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from iris_dataset.reporting import build_report, format_report
from iris_dataset.validation import validate_dataset

from tests.support import (
    EXTRACTION_VERSION,
    create_image,
    manifest_row,
    write_registry,
    write_rows,
)


class DatasetReportingTest(unittest.TestCase):
    def test_empty_report_has_zero_real_items(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            data_root = root / "derived"
            data_root.mkdir()
            manifest = root / "manifest.csv"
            registry = root / "registry.json"
            write_rows(manifest, [])
            write_registry(registry)
            validation = validate_dataset(
                manifest, registry, data_root, {EXTRACTION_VERSION}
            )
            report = build_report(validation)
            self.assertEqual(report.total_items, 0)
            self.assertFalse(report.training_eligible)
            self.assertIn("No real dataset", format_report(report))

    def test_report_uses_actual_manifest_counts(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            data_root = root / "derived"
            data_root.mkdir()
            manifest = root / "manifest.csv"
            registry = root / "registry.json"
            write_registry(registry)
            create_image(data_root / "accident.png", color=(10, 20, 30))
            create_image(data_root / "normal.png", color=(30, 80, 140))
            accident = manifest_row(
                data_root,
                "accident.png",
                item_id="accident",
                label="accident",
                group_id="accident-group",
                event_id="accident-event",
                video_id="accident-video",
            )
            normal = manifest_row(
                data_root,
                "normal.png",
                item_id="normal",
                label="non_accident",
                group_id="normal-group",
                event_id="normal-event",
                video_id="normal-video",
            )
            write_rows(manifest, [accident, normal])
            validation = validate_dataset(
                manifest, registry, data_root, {EXTRACTION_VERSION}
            )
            report = build_report(validation)
            self.assertEqual(report.total_items, 2)
            self.assertEqual(report.accident_items, 1)
            self.assertEqual(report.non_accident_items, 1)
            self.assertEqual(report.unique_source_groups, 2)
            rendered = format_report(report)
            self.assertIn("Counts by source category", rendered)
            self.assertIn("Image dimensions", rendered)


if __name__ == "__main__":
    unittest.main()
