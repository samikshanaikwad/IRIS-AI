from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from iris_dataset.experimental import (
    load_freeze,
    prepare_splits,
    selected_digest,
    validate_experimental_preflight,
)


ROOT = Path(__file__).resolve().parents[3]


class ExperimentalV0Test(unittest.TestCase):
    def test_frozen_v0_passes_experimental_preflight(self) -> None:
        result = validate_experimental_preflight(
            ROOT / "datasets/manifests/classification/v0_candidate_freeze.v1.csv",
            ROOT / "datasets/manifests/classification/v0_experimental_authorization.v1.json",
            ROOT / "datasets/manifests/classification/v0_experimental_split.v1.csv",
            ROOT,
        )
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(result["integrity"]["verified_files"], 1000)
        self.assertTrue(result["test_locked"])

    def test_authorization_fails_when_freeze_digest_changes(self) -> None:
        freeze = ROOT / "datasets/manifests/classification/v0_candidate_freeze.v1.csv"
        auth = ROOT / "datasets/manifests/classification/v0_experimental_authorization.v1.json"
        split = ROOT / "datasets/manifests/classification/v0_experimental_split.v1.csv"
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            changed_freeze = temporary / "freeze.csv"
            changed_freeze.write_bytes(freeze.read_bytes() + b"\n")
            with self.assertRaisesRegex(ValueError, "freeze digest"):
                validate_experimental_preflight(changed_freeze, auth, split, ROOT)

    def test_near_duplicate_components_do_not_cross_splits(self) -> None:
        rows = []
        for index in range(6):
            rows.append(
                {
                    "item_id": f"item-{index}",
                    "label": "accident" if index < 3 else "non_accident",
                    "source_dataset_id": "test",
                    "source_item": f"item-{index}.jpg",
                    "sha256": f"{index + 1:064x}",
                    "perceptual_hash": "0000000000000000" if index < 2 else f"{index:016x}",
                    "source_group_id": f"group-{index}",
                }
            )
        first, first_meta = prepare_splits(rows)
        second, second_meta = prepare_splits(rows)
        self.assertEqual(first, second)
        self.assertEqual(first_meta, second_meta)
        self.assertEqual(
            {row["split"] for row in first if row["item_id"] in {"item-0", "item-1"}},
            {first[0]["split"]},
        )
        self.assertEqual(selected_digest(rows), selected_digest(rows))


if __name__ == "__main__":
    unittest.main()
