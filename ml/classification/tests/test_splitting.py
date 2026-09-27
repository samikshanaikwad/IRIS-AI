from __future__ import annotations

import copy
import unittest

from iris_dataset.manifest import DatasetConfigurationError
from iris_dataset.splitting import assign_group_splits


def _policy(seed: int = 6006):
    return {
        "seed": seed,
        "group_field": "source_group_id",
        "stratify_fields": ["source_dataset_id", "source_category"],
        "targets": {"train": 0.70, "validation": 0.15, "test": 0.15},
    }


def _rows(group_count: int = 20):
    rows = []
    for group_index in range(group_count):
        for frame_index in range(2):
            rows.append(
                {
                    "item_id": f"item-{group_index}-{frame_index}",
                    "source_group_id": f"group-{group_index}",
                    "source_dataset_id": "source",
                    "source_category": f"category-{group_index % 2}",
                    "split": "",
                }
            )
    return rows


class GroupSplitTest(unittest.TestCase):
    def test_split_is_deterministic_for_fixed_seed(self) -> None:
        rows = _rows()
        first = assign_group_splits(copy.deepcopy(rows), _policy())
        second = assign_group_splits(copy.deepcopy(rows), _policy())
        self.assertEqual(first, second)

    def test_all_rows_from_group_share_one_split(self) -> None:
        assigned = assign_group_splits(_rows(), _policy())
        splits_by_group: dict[str, set[str]] = {}
        for row in assigned:
            splits_by_group.setdefault(row["source_group_id"], set()).add(row["split"])
        self.assertTrue(splits_by_group)
        self.assertTrue(all(len(splits) == 1 for splits in splits_by_group.values()))

    def test_target_splits_are_group_based(self) -> None:
        assigned = assign_group_splits(_rows(20), _policy())
        groups_by_split: dict[str, set[str]] = {}
        for row in assigned:
            groups_by_split.setdefault(row["split"], set()).add(
                row["source_group_id"]
            )
        self.assertEqual(len(groups_by_split["train"]), 14)
        self.assertEqual(len(groups_by_split["validation"]), 4)
        self.assertEqual(len(groups_by_split["test"]), 2)

    def test_external_test_group_is_preserved(self) -> None:
        rows = _rows(4)
        rows.extend(
            [
                {
                    "item_id": "external-1",
                    "source_group_id": "external-group",
                    "source_dataset_id": "external-source",
                    "source_category": "external-category",
                    "split": "external_test",
                },
                {
                    "item_id": "external-2",
                    "source_group_id": "external-group",
                    "source_dataset_id": "external-source",
                    "source_category": "external-category",
                    "split": "external_test",
                },
            ]
        )
        assigned = assign_group_splits(rows, _policy())
        external = [row for row in assigned if row["source_group_id"] == "external-group"]
        self.assertEqual({row["split"] for row in external}, {"external_test"})

    def test_missing_group_is_rejected(self) -> None:
        rows = _rows(1)
        rows[0]["source_group_id"] = ""
        with self.assertRaises(DatasetConfigurationError):
            assign_group_splits(rows, _policy())

    def test_existing_cross_split_group_is_rejected(self) -> None:
        rows = _rows(1)
        rows[0]["split"] = "train"
        rows[1]["split"] = "test"
        with self.assertRaises(DatasetConfigurationError):
            assign_group_splits(rows, _policy())


if __name__ == "__main__":
    unittest.main()
