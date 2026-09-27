from __future__ import annotations

import hashlib
import math
from collections import defaultdict
from pathlib import Path
from typing import Any

from .manifest import DatasetConfigurationError, load_json

INTERNAL_SPLITS = ("train", "validation", "test")


def load_split_policy(path: Path) -> dict[str, Any]:
    policy = load_json(path)
    if not isinstance(policy, dict):
        raise DatasetConfigurationError("Split policy root must be an object")
    targets = policy.get("targets")
    if not isinstance(targets, dict) or set(targets) != set(INTERNAL_SPLITS):
        raise DatasetConfigurationError(
            "Split targets must define train, validation, and test"
        )
    try:
        fractions = {name: float(targets[name]) for name in INTERNAL_SPLITS}
    except (TypeError, ValueError) as error:
        raise DatasetConfigurationError("Split targets must be numeric") from error
    if any(value <= 0 or value >= 1 for value in fractions.values()):
        raise DatasetConfigurationError("Every split target must be between 0 and 1")
    if not math.isclose(sum(fractions.values()), 1.0, abs_tol=1e-9):
        raise DatasetConfigurationError("Split targets must sum to 1.0")
    if not isinstance(policy.get("seed"), int):
        raise DatasetConfigurationError("Split seed must be an integer")
    if not isinstance(policy.get("group_field"), str):
        raise DatasetConfigurationError("Split group_field must be a string")
    fields = policy.get("stratify_fields")
    if not isinstance(fields, list) or not all(
        isinstance(field, str) and field for field in fields
    ):
        raise DatasetConfigurationError("stratify_fields must be a string list")
    policy["targets"] = fractions
    return policy


def _allocation(total: int, targets: dict[str, float]) -> dict[str, int]:
    exact = {name: total * targets[name] for name in INTERNAL_SPLITS}
    counts = {name: math.floor(exact[name]) for name in INTERNAL_SPLITS}
    remainder = total - sum(counts.values())
    ranked = sorted(
        INTERNAL_SPLITS,
        key=lambda name: (-(exact[name] - counts[name]), INTERNAL_SPLITS.index(name)),
    )
    for name in ranked[:remainder]:
        counts[name] += 1
    return counts


def _stable_key(seed: int, group_id: str) -> str:
    return hashlib.sha256(f"{seed}:{group_id}".encode("utf-8")).hexdigest()


def _group_stratum(
    group_rows: list[dict[str, str]], fields: list[str]
) -> tuple[tuple[str, tuple[str, ...]], ...]:
    return tuple(
        (field, tuple(sorted({row.get(field, "") for row in group_rows})))
        for field in fields
    )


def assign_group_splits(
    rows: list[dict[str, str]], policy: dict[str, Any]
) -> list[dict[str, str]]:
    group_field = policy["group_field"]
    seed = policy["seed"]
    targets = policy["targets"]
    stratify_fields = policy["stratify_fields"]
    grouped: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        group_id = row.get(group_field, "")
        if not group_id:
            raise DatasetConfigurationError(
                f"Cannot split a row with an empty {group_field}"
            )
        grouped[group_id].append(row)

    assignments: dict[str, str] = {}
    strata: dict[
        tuple[tuple[str, tuple[str, ...]], ...], list[str]
    ] = defaultdict(list)
    for group_id, group_rows in grouped.items():
        existing = {row.get("split", "") for row in group_rows} - {""}
        if len(existing) > 1:
            raise DatasetConfigurationError(
                f"Source group {group_id!r} already spans splits {sorted(existing)}"
            )
        if existing == {"external_test"}:
            assignments[group_id] = "external_test"
            continue
        if "external_test" in existing:
            raise DatasetConfigurationError(
                f"Source group {group_id!r} mixes external_test with internal data"
            )
        strata[_group_stratum(group_rows, stratify_fields)].append(group_id)

    for group_ids in strata.values():
        ordered = sorted(group_ids, key=lambda group_id: _stable_key(seed, group_id))
        counts = _allocation(len(ordered), targets)
        offset = 0
        for split in INTERNAL_SPLITS:
            split_groups = ordered[offset : offset + counts[split]]
            for group_id in split_groups:
                assignments[group_id] = split
            offset += counts[split]

    output: list[dict[str, str]] = []
    for row in rows:
        copied = dict(row)
        copied["split"] = assignments[row[group_field]]
        output.append(copied)
    return output
