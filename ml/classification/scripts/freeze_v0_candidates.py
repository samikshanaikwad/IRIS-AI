"""Create and validate the deterministic IRIS V0 reviewed candidate freeze."""

from __future__ import annotations

import argparse
import csv
from collections import Counter
from pathlib import Path

from iris_dataset.duplicates import find_near_duplicate_pairs
from iris_dataset.mendeley import load_review_inventory

FREEZE_VERSION = "iris-classification-v0-candidate-freeze-v1"
FREEZE_FIELDS = (
    "freeze_version",
    "item_id",
    "label",
    "source_dataset_id",
    "source_dataset_version",
    "source_item",
    "source_reference",
    "source_group_id",
    "sha256",
    "perceptual_hash",
    "width",
    "height",
    "annotation_status",
    "technical_status",
    "rights_status",
    "label_basis",
    "reviewer",
    "review_date",
    "provenance_note",
)


def _batch_rows(paths: list[Path]) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for path in paths:
        with path.open("r", encoding="utf-8-sig", newline="") as handle:
            reader = csv.DictReader(handle)
            expected = {
                "source_item",
                "sha256",
                "review_decision",
                "label_basis",
                "reviewer",
                "review_date",
                "rationale",
            }
            if not expected.issubset(set(reader.fieldnames or ())):
                raise ValueError(f"Review batch header is invalid: {path}")
            rows.extend(
                {key: (value or "").strip() for key, value in row.items()}
                for row in reader
            )
    return rows


def _read_quarantine(path: Path) -> set[str]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return {row["source_item"] for row in csv.DictReader(handle)}


def build_freeze(
    *,
    accident_inventory: Path,
    dats_inventory: Path,
    accident_batches: list[Path],
    dats_batches: list[Path],
    quarantine: Path,
    output: Path,
    archive_references: dict[str, str],
) -> dict[str, int]:
    accident_inventory_rows = {
        row["source_item"]: row for row in load_review_inventory(accident_inventory)
    }
    dats_inventory_rows = {
        row["source_item"]: row for row in load_review_inventory(dats_inventory)
    }
    quarantined = _read_quarantine(quarantine)
    selected: list[dict[str, str]] = []
    for label, paths, inventory_rows in (
        ("accident", accident_batches, accident_inventory_rows),
        ("non_accident", dats_batches, dats_inventory_rows),
    ):
        candidates: list[dict[str, str]] = []
        seen_items: set[str] = set()
        for batch_row in _batch_rows(paths):
            if batch_row["review_decision"] != label:
                continue
            source_item = batch_row["source_item"]
            row = inventory_rows.get(source_item)
            if row is None or source_item in seen_items:
                continue
            if label == "accident" and source_item in quarantined:
                continue
            if row["sha256"] != batch_row["sha256"]:
                raise ValueError(f"Batch hash differs from inventory: {source_item}")
            if row["technical_status"] != "READABLE":
                raise ValueError(f"Selected source is not readable: {source_item}")
            if label == "accident" and row["annotation_status"] != "VALID_ACCIDENT_ANNOTATION":
                raise ValueError(f"Selected accident source is not eligible: {source_item}")
            if label == "non_accident" and row["source_dataset_id"] != "dats-2022-mendeley":
                raise ValueError(f"Selected negative source is not DATS: {source_item}")
            selected.append(
                {
                    **row,
                    "label": label,
                    "reviewer": batch_row["reviewer"],
                    "review_date": batch_row["review_date"],
                    "label_basis": batch_row["label_basis"],
                    "source_reference": (
                        f"{archive_references[row['source_dataset_id']]}::{source_item}"
                    ),
                    "provenance_note": (
                        "Mendeley declares CC BY 4.0; source imagery was reported as "
                        "collected through Google Image Search, so underlying individual "
                        "image provenance remains unresolved."
                        if label == "accident"
                        else "DATS object annotations are not used as semantic labels; this "
                        "item was accepted through explicit IRIS human review."
                    ),
                }
            )
            seen_items.add(source_item)
        selected_for_label = [row for row in selected if row["label"] == label]
        if len(selected_for_label) < 500:
            raise ValueError(f"Only {len(selected_for_label)} explicit {label} candidates available")
        selected = [row for row in selected if row["label"] != label]
        selected.extend(sorted(selected_for_label, key=lambda row: row["source_item"])[:500])

    selected.sort(key=lambda row: (row["label"], row["source_item"]))
    if len(selected) != 1000:
        raise ValueError(f"Expected 1000 selected rows, found {len(selected)}")
    hashes = [row["sha256"] for row in selected]
    if len(set(hashes)) != len(hashes):
        raise ValueError("Exact SHA-256 duplicate exists in the selected freeze")
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FREEZE_FIELDS, lineterminator="\n")
        writer.writeheader()
        for index, row in enumerate(selected, start=1):
            writer.writerow(
                {
                    "freeze_version": FREEZE_VERSION,
                    "item_id": f"v0-{index:04d}-{row['label']}-{row['sha256'][:12]}",
                    **{field: row.get(field, "") for field in FREEZE_FIELDS if field not in {"freeze_version", "item_id"}},
                }
            )
    pairs = find_near_duplicate_pairs(
        [(index, row["perceptual_hash"]) for index, row in enumerate(selected)],
        maximum_distance=4,
    )
    cross_class_near = sum(
        1
        for first, second, _distance in pairs
        if selected[first]["label"] != selected[second]["label"]
    )
    counts = Counter(row["label"] for row in selected)
    return {
        "rows": len(selected),
        "accident": counts["accident"],
        "non_accident": counts["non_accident"],
        "exact_unique_sha256": len(set(hashes)),
        "near_duplicate_pairs_distance_le_4": len(pairs),
        "cross_class_near_duplicate_pairs": cross_class_near,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--accident-inventory", type=Path, required=True)
    parser.add_argument("--dats-inventory", type=Path, required=True)
    parser.add_argument("--accident-batch", type=Path, action="append", required=True)
    parser.add_argument("--dats-batch", type=Path, action="append", required=True)
    parser.add_argument("--quarantine", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = build_freeze(
        accident_inventory=args.accident_inventory,
        dats_inventory=args.dats_inventory,
        accident_batches=args.accident_batch,
        dats_batches=args.dats_batch,
        quarantine=args.quarantine,
        output=args.output,
        archive_references={
            "accident-detection-9k-mendeley": "datasets/raw/classification/accident_detection_9k/v2/Accident_Detection.zip",
            "dats-2022-mendeley": "datasets/raw/classification/dats_2022/v2/DATS_2022.zip",
        },
    )
    print(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
