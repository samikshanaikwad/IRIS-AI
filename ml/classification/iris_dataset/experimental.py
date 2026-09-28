"""Rights-scoped experimental authorization and split preparation for V0."""

from __future__ import annotations

import csv
import hashlib
import io
import json
import zipfile
from collections import defaultdict
from pathlib import Path
from typing import Any

from PIL import Image

from .duplicates import find_near_duplicate_pairs

EXPERIMENTAL_AUTH_VERSION = "iris-v0-experimental-authorization-v1"
EXPERIMENTAL_SPLIT_VERSION = "iris-v0-experimental-split-v1"
SPLIT_FIELDS = (
    "split_version",
    "item_id",
    "label",
    "source_dataset_id",
    "source_item",
    "sha256",
    "perceptual_hash",
    "source_group_id",
    "leakage_component_id",
    "split",
    "test_locked",
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def selected_digest(rows: list[dict[str, str]]) -> str:
    canonical = "".join(
        f"{row['item_id']}|{row['label']}|{row['source_dataset_id']}|"
        f"{row['source_item']}|{row['sha256']}\n"
        for row in sorted(rows, key=lambda row: row["item_id"])
    )
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def load_freeze(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != 1000:
        raise ValueError(f"V0 freeze must contain 1000 rows, found {len(rows)}")
    if {row.get("label", "") for row in rows} != {"accident", "non_accident"}:
        raise ValueError("V0 freeze must contain both classes")
    if sum(row["label"] == "accident" for row in rows) != 500:
        raise ValueError("V0 freeze must contain exactly 500 accident rows")
    if sum(row["label"] == "non_accident" for row in rows) != 500:
        raise ValueError("V0 freeze must contain exactly 500 non_accident rows")
    if len({row["sha256"] for row in rows}) != 1000:
        raise ValueError("V0 freeze contains duplicate SHA-256 values")
    if any(row["label"] == "accident" and row["rights_status"] != "REVIEW_REQUIRED" for row in rows):
        raise ValueError("AccidentDetection rights status must remain REVIEW_REQUIRED")
    return rows


def verify_archived_sources(
    rows: list[dict[str, str]], repository_root: Path
) -> dict[str, int]:
    archives: dict[str, zipfile.ZipFile] = {}
    verified = 0
    try:
        for row in rows:
            reference = row["source_reference"]
            archive_text, member = reference.split("::", 1)
            archive_path = repository_root / archive_text
            archive = archives.get(str(archive_path))
            if archive is None:
                archive = zipfile.ZipFile(archive_path)
                archives[str(archive_path)] = archive
            try:
                data = archive.read(member)
            except KeyError as error:
                raise ValueError(f"Freeze source member is missing: {member}") from error
            if hashlib.sha256(data).hexdigest() != row["sha256"]:
                raise ValueError(f"Freeze source hash mismatch: {row['item_id']}")
            with Image.open(io.BytesIO(data)) as image:
                image.verify()
            verified += 1
    finally:
        for archive in archives.values():
            archive.close()
    return {"verified_files": verified, "total_files": len(rows)}


class _DisjointSet:
    def __init__(self, size: int) -> None:
        self.parent = list(range(size))

    def find(self, value: int) -> int:
        while self.parent[value] != value:
            self.parent[value] = self.parent[self.parent[value]]
            value = self.parent[value]
        return value

    def union(self, left: int, right: int) -> None:
        left_root = self.find(left)
        right_root = self.find(right)
        if left_root != right_root:
            self.parent[right_root] = left_root


def prepare_splits(
    rows: list[dict[str, str]], seed: int = 6006
) -> tuple[list[dict[str, str]], dict[str, Any]]:
    pairs = find_near_duplicate_pairs(
        [(index, row["perceptual_hash"]) for index, row in enumerate(rows)], 4
    )
    components = _DisjointSet(len(rows))
    for left, right, _distance in pairs:
        components.union(left, right)
    component_rows: dict[int, list[int]] = defaultdict(list)
    for index in range(len(rows)):
        component_rows[components.find(index)].append(index)
    component_ids = {
        root: f"v0-near-component-{number:04d}"
        for number, root in enumerate(sorted(component_rows), start=1)
    }
    assignments: dict[int, str] = {}
    target = {"train": 350, "validation": 75, "test": 75}
    for label in ("accident", "non_accident"):
        label_components = [
            (root, indices)
            for root, indices in component_rows.items()
            if rows[indices[0]]["label"] == label
        ]
        label_components.sort(
            key=lambda item: hashlib.sha256(
                f"{seed}:{component_ids[item[0]]}".encode("utf-8")
            ).hexdigest()
        )
        remaining = dict(target)
        for root, indices in label_components:
            choices = sorted(
                remaining,
                key=lambda split: (-remaining[split], ("train", "validation", "test").index(split)),
            )
            chosen = next((split for split in choices if remaining[split] >= len(indices)), choices[0])
            for index in indices:
                assignments[index] = chosen
            remaining[chosen] -= len(indices)

    output: list[dict[str, str]] = []
    for index, row in enumerate(rows):
        split = assignments[index]
        output.append(
            {
                "split_version": EXPERIMENTAL_SPLIT_VERSION,
                "item_id": row["item_id"],
                "label": row["label"],
                "source_dataset_id": row["source_dataset_id"],
                "source_item": row["source_item"],
                "sha256": row["sha256"],
                "perceptual_hash": row["perceptual_hash"],
                "source_group_id": row["source_group_id"],
                "leakage_component_id": component_ids[components.find(index)],
                "split": split,
                "test_locked": "true" if split == "test" else "false",
            }
        )
    counts = {
        f"{label}_{split}": sum(
            row["label"] == label and row["split"] == split for row in output
        )
        for label in ("accident", "non_accident")
        for split in ("train", "validation", "test")
    }
    return output, {
        "seed": seed,
        "near_duplicate_pairs": len(pairs),
        "near_duplicate_components": len(component_rows),
        "counts": counts,
        "test_locked": True,
    }


def write_split_manifest(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=SPLIT_FIELDS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def write_authorization(
    path: Path,
    freeze_path: Path,
    freeze_digest: str,
    rows: list[dict[str, str]],
    split_metadata: dict[str, Any],
) -> None:
    payload = {
        "authorization_version": EXPERIMENTAL_AUTH_VERSION,
        "scope": {
            "task": "TASK 006",
            "dataset": "IRIS V0 accident/non-accident classifier",
            "freeze_manifest": freeze_path.as_posix(),
            "freeze_manifest_sha256": freeze_digest,
            "selected_sample_digest": selected_digest(rows),
            "use": "local experimental academic/research model development only",
            "production_release": False,
        },
        "rights": {
            "accident_detection_status": "REVIEW_REQUIRED",
            "dats_status": "APPROVED",
            "provenance_warning": (
                "AccidentDetection-9k underlying individual-image provenance is unresolved "
                "because source imagery was reported as collected through Google Image Search."
            ),
            "does_not_imply_production_or_release_clearance": True,
        },
        "counts": {"total": len(rows), "accident": 500, "non_accident": 500},
        "split": split_metadata,
        "test_policy": (
            "Test labels are locked before training and may only be used for one final "
            "held-out evaluation after model and threshold decisions are frozen."
        ),
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def validate_experimental_preflight(
    freeze_path: Path,
    authorization_path: Path,
    split_path: Path,
    repository_root: Path,
) -> dict[str, Any]:
    rows = load_freeze(freeze_path)
    authorization = json.loads(authorization_path.read_text(encoding="utf-8"))
    freeze_digest = sha256_file(freeze_path)
    expected_scope = authorization.get("scope", {})
    if authorization.get("authorization_version") != EXPERIMENTAL_AUTH_VERSION:
        raise ValueError("Unsupported experimental authorization version")
    if expected_scope.get("freeze_manifest_sha256") != freeze_digest:
        raise ValueError("Experimental authorization freeze digest does not match")
    if expected_scope.get("selected_sample_digest") != selected_digest(rows):
        raise ValueError("Experimental authorization selected-sample digest does not match")
    if expected_scope.get("production_release") is not False:
        raise ValueError("Experimental authorization cannot authorize production release")
    if authorization.get("counts") != {"total": 1000, "accident": 500, "non_accident": 500}:
        raise ValueError("Experimental authorization counts are invalid")
    integrity = verify_archived_sources(rows, repository_root)
    with split_path.open("r", encoding="utf-8-sig", newline="") as handle:
        split_rows = list(csv.DictReader(handle))
    if len(split_rows) != 1000:
        raise ValueError("Experimental split must contain 1000 rows")
    freeze_by_item = {row["item_id"]: row for row in rows}
    split_by_item = {row["item_id"]: row for row in split_rows}
    if set(freeze_by_item) != set(split_by_item):
        raise ValueError("Experimental split sample set does not match the freeze")
    if len(split_by_item) != 1000:
        raise ValueError("Experimental split contains duplicate item IDs")
    for item_id, row in split_by_item.items():
        frozen = freeze_by_item[item_id]
        if row["sha256"] != frozen["sha256"] or row["label"] != frozen["label"]:
            raise ValueError(f"Experimental split changes frozen sample: {item_id}")
        if row["split"] not in {"train", "validation", "test"}:
            raise ValueError(f"Invalid experimental split: {item_id}")
        if row["test_locked"] != ("true" if row["split"] == "test" else "false"):
            raise ValueError(f"Invalid test lock metadata: {item_id}")
    component_splits: dict[str, set[str]] = defaultdict(set)
    for row in split_rows:
        component_splits[row["leakage_component_id"]].add(row["split"])
    crossing = [component for component, splits in component_splits.items() if len(splits) > 1]
    if crossing:
        raise ValueError(f"Near-duplicate components cross splits: {crossing[:5]}")
    counts = {
        f"{label}_{split}": sum(
            row["label"] == label and row["split"] == split
            for row in split_rows
        )
        for label in ("accident", "non_accident")
        for split in ("train", "validation", "test")
    }
    return {
        "status": "PASS",
        "freeze_manifest_sha256": freeze_digest,
        "selected_sample_digest": selected_digest(rows),
        "integrity": integrity,
        "counts": counts,
        "near_duplicate_components": len(component_splits),
        "test_locked": all(row["test_locked"] == "true" for row in split_rows if row["split"] == "test"),
    }
