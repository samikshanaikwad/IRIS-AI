from __future__ import annotations

import csv
import hashlib
import json
import re
import xml.etree.ElementTree as element_tree
import zipfile
from collections import Counter, defaultdict
from dataclasses import dataclass, replace
from pathlib import Path, PurePosixPath
from typing import Any, Iterable

from .duplicates import PerceptualHashIndex
from .image_tools import ImageDecodeError, probe_image_bytes, sha256_file

INSPECTION_VERSION = "iris-mendeley-source-inspection-v1"
REVIEW_VERSION = "iris-classification-source-review-v1"
NEAR_DUPLICATE_THRESHOLD = 4
SUPPORTED_IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png"}

REVIEW_FIELDS = (
    "review_version",
    "inspection_tool_version",
    "source_dataset_id",
    "source_dataset_version",
    "source_item",
    "source_filename",
    "publisher_split",
    "source_group_id",
    "group_basis",
    "annotation_status",
    "annotation_count",
    "technical_status",
    "rights_status",
    "sha256",
    "perceptual_hash",
    "width",
    "height",
    "decoded_format",
    "review_decision",
    "label_basis",
    "reviewer",
    "review_date",
    "rationale",
)

REVIEW_DECISIONS = {
    "pending",
    "accident",
    "non_accident",
    "exclude_ambiguous",
    "exclude_visible_accident",
    "exclude_irrelevant",
    "exclude_corrupt",
}

REVIEW_BATCH_FIELDS = (
    "source_item",
    "sha256",
    "review_file",
    "review_decision",
    "label_basis",
    "reviewer",
    "review_date",
    "rationale",
)

LEGACY_REVIEW_FIELDS = (
    "review_version",
    "source_dataset_id",
    "source_dataset_version",
    "source_item",
    "source_filename",
    "publisher_split",
    "source_group_id",
    "group_basis",
    "annotation_status",
    "annotation_count",
    "technical_status",
    "rights_status",
    "sha256",
    "perceptual_hash",
    "width",
    "height",
    "decoded_format",
    "semantic_review_status",
    "reviewed_label",
    "exclusion_reason",
    "reviewer",
    "review_date",
    "rationale",
)


class SourceInspectionError(ValueError):
    """Raised when a downloaded source does not match its documented layout."""


@dataclass(frozen=True)
class InspectedImage:
    source_item: str
    source_filename: str
    publisher_split: str
    source_group_id: str
    group_basis: str
    annotation_status: str
    annotation_count: int
    technical_status: str
    rights_status: str
    sha256: str
    perceptual_hash: str
    width: int
    height: int
    decoded_format: str


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _normalise_member_name(name: str) -> str:
    return str(PurePosixPath(name.replace("\\", "/")))


def _review_row(
    image: InspectedImage,
    dataset_id: str,
    dataset_version: str,
) -> dict[str, str]:
    return {
        "review_version": REVIEW_VERSION,
        "inspection_tool_version": INSPECTION_VERSION,
        "source_dataset_id": dataset_id,
        "source_dataset_version": dataset_version,
        "source_item": image.source_item,
        "source_filename": image.source_filename,
        "publisher_split": image.publisher_split,
        "source_group_id": image.source_group_id,
        "group_basis": image.group_basis,
        "annotation_status": image.annotation_status,
        "annotation_count": str(image.annotation_count),
        "technical_status": image.technical_status,
        "rights_status": image.rights_status,
        "sha256": image.sha256,
        "perceptual_hash": image.perceptual_hash,
        "width": str(image.width) if image.width else "",
        "height": str(image.height) if image.height else "",
        "decoded_format": image.decoded_format,
        "review_decision": "pending",
        "label_basis": "",
        "reviewer": "",
        "review_date": "",
        "rationale": "",
    }


def write_review_inventory(path: Path, rows: Iterable[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=REVIEW_FIELDS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    temporary.replace(path)


def load_review_inventory(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        actual_fields = tuple(reader.fieldnames or ())
        if actual_fields not in {REVIEW_FIELDS, LEGACY_REVIEW_FIELDS}:
            raise SourceInspectionError(
                f"Review inventory header does not match {REVIEW_VERSION}: {path}"
            )
        rows = list(reader)
    if actual_fields == REVIEW_FIELDS:
        return [
            {field: (row.get(field) or "").strip() for field in REVIEW_FIELDS}
            for row in rows
        ]
    converted: list[dict[str, str]] = []
    for row in rows:
        legacy_status = (row.get("semantic_review_status") or "").strip().lower()
        legacy_label = (row.get("reviewed_label") or "").strip().lower()
        if legacy_label in {"accident", "non_accident"}:
            decision = legacy_label
        elif legacy_status in {"", "pending", "not_assessed"}:
            decision = "pending"
        elif legacy_status in REVIEW_DECISIONS:
            decision = legacy_status
        else:
            raise SourceInspectionError(
                "Legacy review decision cannot be migrated for "
                f"{row.get('source_item')!r}"
            )
        converted.append(
            {
                **{
                    field: (row.get(field) or "").strip()
                    for field in REVIEW_FIELDS
                    if field in row
                },
                "review_decision": decision,
                "label_basis": "",
            }
        )
        converted[-1] = {
            field: converted[-1].get(field, "") for field in REVIEW_FIELDS
        }
    return converted


def update_review_inventory(
    path: Path, fresh_rows: list[dict[str, str]]
) -> None:
    if path.exists():
        existing = {
            row["source_item"]: row for row in load_review_inventory(path)
        }
        for row in fresh_rows:
            prior = existing.get(row["source_item"])
            if prior is None or prior["sha256"] != row["sha256"]:
                continue
            for field in (
                "review_decision",
                "label_basis",
                "reviewer",
                "review_date",
                "rationale",
            ):
                row[field] = prior[field]
    write_review_inventory(path, fresh_rows)


def validate_review_rows(rows: list[dict[str, str]]) -> dict[str, Any]:
    errors: list[str] = []
    decisions: Counter[str] = Counter()
    seen_items: set[str] = set()
    accepted_with_approved_rights = 0
    for row_number, row in enumerate(rows, start=2):
        source_item = row["source_item"]
        decision = row["review_decision"]
        decisions[decision] += 1
        if row["review_version"] != REVIEW_VERSION:
            errors.append(f"row {row_number}: unsupported review_version")
        if row["inspection_tool_version"] != INSPECTION_VERSION:
            errors.append(f"row {row_number}: unsupported inspection_tool_version")
        if not source_item:
            errors.append(f"row {row_number}: source_item is required")
        elif source_item in seen_items:
            errors.append(f"row {row_number}: duplicate source_item {source_item!r}")
        else:
            seen_items.add(source_item)
        if decision not in REVIEW_DECISIONS:
            errors.append(f"row {row_number}: unsupported review_decision {decision!r}")
            continue
        if decision == "pending":
            if any(row[field] for field in ("label_basis", "reviewer", "review_date")):
                errors.append(
                    f"row {row_number}: pending review cannot contain completed "
                    "review metadata"
                )
            continue
        for field in ("label_basis", "reviewer", "review_date"):
            if not row[field]:
                errors.append(
                    f"row {row_number}: {field} is required for decision {decision}"
                )
        if row["review_date"] and not re.fullmatch(
            r"\d{4}-\d{2}-\d{2}", row["review_date"]
        ):
            errors.append(f"row {row_number}: review_date must use YYYY-MM-DD")
        if (
            decision in {"accident", "non_accident"}
            and row["technical_status"] != "READABLE"
        ):
            errors.append(
                f"row {row_number}: unreadable evidence cannot receive an "
                "accepted label"
            )
        if (
            decision == "accident"
            and row["source_dataset_id"] != "accident-detection-9k-mendeley"
        ):
            errors.append(
                f"row {row_number}: DATS candidates must use "
                "exclude_visible_accident, not accident"
            )
        if (
            decision == "accident"
            and row["annotation_status"] != "VALID_ACCIDENT_ANNOTATION"
        ):
            errors.append(
                f"row {row_number}: accident requires a valid publisher "
                "Accident annotation"
            )
        if (
            decision == "non_accident"
            and row["source_dataset_id"] != "dats-2022-mendeley"
        ):
            errors.append(
                f"row {row_number}: AccidentDetection candidates cannot be "
                "accepted as non_accident"
            )
        if (
            decision in {"accident", "non_accident"}
            and row["rights_status"] == "APPROVED"
            and row["technical_status"] == "READABLE"
        ):
            accepted_with_approved_rights += 1
    return {
        "rows": len(rows),
        "decision_counts": dict(sorted(decisions.items())),
        "validation_errors": errors,
        "accepted_items_with_approved_rights": accepted_with_approved_rights,
    }


def validate_review_inventory(path: Path) -> dict[str, Any]:
    return validate_review_rows(load_review_inventory(path))


def create_review_batch(
    archive_path: Path,
    review_inventory_path: Path,
    output_root: Path,
    source_dataset_id: str,
    start: int,
    limit: int,
) -> dict[str, Any]:
    if start < 0 or limit <= 0:
        raise SourceInspectionError(
            "Review batch start must be non-negative and limit positive"
        )
    rows = [
        row
        for row in load_review_inventory(review_inventory_path)
        if row["source_dataset_id"] == source_dataset_id
        and row["review_decision"] == "pending"
        and row["technical_status"] == "READABLE"
    ]
    selected = rows[start : start + limit]
    output_root.mkdir(parents=True, exist_ok=True)
    image_root = output_root / "images"
    image_root.mkdir(parents=True, exist_ok=True)
    batch_rows: list[dict[str, str]] = []
    with zipfile.ZipFile(archive_path) as archive:
        available = {
            _normalise_member_name(member.filename): member
            for member in archive.infolist()
            if not member.is_dir()
        }
        for offset, row in enumerate(selected, start=start + 1):
            member = available.get(row["source_item"])
            if member is None:
                raise SourceInspectionError(
                    f"Review source item is absent from archive: {row['source_item']}"
                )
            suffix = PurePosixPath(row["source_filename"]).suffix.lower()
            review_name = f"{offset:06d}_{row['sha256'][:12]}{suffix}"
            review_path = image_root / review_name
            source_bytes = archive.read(member)
            source_hash = _sha256_bytes(source_bytes)
            if source_hash != row["sha256"]:
                raise SourceInspectionError(
                    "Review source hash no longer matches the inventory: "
                    f"{row['source_item']}"
                )
            review_path.write_bytes(source_bytes)
            batch_rows.append(
                {
                    "source_item": row["source_item"],
                    "sha256": source_hash,
                    "review_file": f"images/{review_name}",
                    "review_decision": "pending",
                    "label_basis": "",
                    "reviewer": "",
                    "review_date": "",
                    "rationale": "",
                }
            )
    batch_path = output_root / "review_batch.csv"
    with batch_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle, fieldnames=REVIEW_BATCH_FIELDS, lineterminator="\n"
        )
        writer.writeheader()
        writer.writerows(batch_rows)
    return {
        "available_pending_rows": len(rows),
        "batch_start": start,
        "batch_items": len(batch_rows),
        "batch_path": batch_path.as_posix(),
    }


def apply_review_batch(
    review_inventory_path: Path, batch_path: Path
) -> dict[str, Any]:
    master_rows = load_review_inventory(review_inventory_path)
    master_by_item = {row["source_item"]: row for row in master_rows}
    with batch_path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        if tuple(reader.fieldnames or ()) != REVIEW_BATCH_FIELDS:
            raise SourceInspectionError(f"Review batch header is invalid: {batch_path}")
        batch_rows = [
            {field: (row.get(field) or "").strip() for field in REVIEW_BATCH_FIELDS}
            for row in reader
        ]
    applied = 0
    for batch_row in batch_rows:
        decision = batch_row["review_decision"]
        if decision == "pending":
            continue
        if decision not in REVIEW_DECISIONS:
            raise SourceInspectionError(
                f"Unsupported review_decision {decision!r} for "
                f"{batch_row['source_item']}"
            )
        master_row = master_by_item.get(batch_row["source_item"])
        if master_row is None:
            raise SourceInspectionError(
                "Review batch item is absent from inventory: "
                f"{batch_row['source_item']}"
            )
        if batch_row["sha256"] != master_row["sha256"]:
            raise SourceInspectionError(
                "Review batch source hash no longer matches the inventory: "
                f"{batch_row['source_item']}"
            )
        for field in (
            "review_decision",
            "label_basis",
            "reviewer",
            "review_date",
            "rationale",
        ):
            master_row[field] = batch_row[field]
        applied += 1
    validation = validate_review_rows(master_rows)
    if validation["validation_errors"]:
        raise SourceInspectionError(
            "Review decisions are invalid: "
            + "; ".join(validation["validation_errors"][:10])
        )
    write_review_inventory(review_inventory_path, master_rows)
    return {"applied_decisions": applied, **validation}


def _duplicate_summary(images: list[InspectedImage]) -> dict[str, Any]:
    hashes: dict[str, list[int]] = defaultdict(list)
    source_groups: set[str] = set()
    group_splits: dict[str, set[str]] = defaultdict(set)
    for index, image in enumerate(images):
        if image.sha256:
            hashes[image.sha256].append(index)
        if image.source_group_id:
            source_groups.add(image.source_group_id)
        if image.source_group_id and image.publisher_split:
            group_splits[image.source_group_id].add(image.publisher_split)

    exact_groups = [indices for indices in hashes.values() if len(indices) > 1]
    exact_cross_split = [
        indices
        for indices in exact_groups
        if len({images[index].publisher_split for index in indices}) > 1
    ]
    near_index = PerceptualHashIndex()
    non_exact_near_count = 0
    cross_split_near_count = 0
    near_examples: list[dict[str, Any]] = []
    cross_split_examples: list[dict[str, Any]] = []
    for image_index, image in enumerate(images):
        if not image.perceptual_hash:
            continue
        for prior_index, distance in near_index.query(
            image.perceptual_hash, NEAR_DUPLICATE_THRESHOLD
        ):
            prior = images[prior_index]
            if image.sha256 == prior.sha256:
                continue
            non_exact_near_count += 1
            example = {
                "left": prior.source_item,
                "right": image.source_item,
                "hamming_distance": distance,
            }
            if len(near_examples) < 25:
                near_examples.append(example)
            if image.publisher_split != prior.publisher_split:
                cross_split_near_count += 1
                if len(cross_split_examples) < 25:
                    cross_split_examples.append(example)
        near_index.add(image.perceptual_hash, image_index)

    return {
        "exact_duplicate_groups": len(exact_groups),
        "exact_duplicate_items": sum(len(group) for group in exact_groups),
        "cross_split_exact_duplicate_groups": len(exact_cross_split),
        "near_duplicate_threshold_hamming_bits": NEAR_DUPLICATE_THRESHOLD,
        "non_exact_near_duplicate_pairs": non_exact_near_count,
        "cross_split_near_duplicate_pairs": cross_split_near_count,
        "near_duplicate_examples": near_examples,
        "cross_split_near_duplicate_examples": cross_split_examples,
        "source_groups": len(source_groups),
        "source_groups_in_multiple_publisher_splits": sum(
            len(splits) > 1 for splits in group_splits.values()
        ),
    }


def _apply_conservative_leakage_groups(
    images: list[InspectedImage], dataset_prefix: str
) -> tuple[list[InspectedImage], dict[str, int]]:
    parents = list(range(len(images)))

    def find(index: int) -> int:
        while parents[index] != index:
            parents[index] = parents[parents[index]]
            index = parents[index]
        return index

    def union(left: int, right: int) -> None:
        left_root = find(left)
        right_root = find(right)
        if left_root != right_root:
            parents[right_root] = left_root

    group_first: dict[str, int] = {}
    hash_first: dict[str, int] = {}
    near_index = PerceptualHashIndex()
    near_edges = 0
    exact_edges = 0
    for index, image in enumerate(images):
        first_group_item = group_first.setdefault(image.source_group_id, index)
        union(first_group_item, index)
        if image.sha256:
            first_hash_item = hash_first.setdefault(image.sha256, index)
            if first_hash_item != index:
                exact_edges += 1
                union(first_hash_item, index)
        if image.perceptual_hash:
            for prior_index, _ in near_index.query(
                image.perceptual_hash, NEAR_DUPLICATE_THRESHOLD
            ):
                if image.sha256 != images[prior_index].sha256:
                    near_edges += 1
                    union(prior_index, index)
            near_index.add(image.perceptual_hash, index)

    component_items: dict[int, list[int]] = defaultdict(list)
    for index in range(len(images)):
        component_items[find(index)].append(index)
    updated = list(images)
    for indices in component_items.values():
        stable_items = sorted(images[index].source_item for index in indices)
        digest = hashlib.sha256(
            "\n".join(stable_items).encode("utf-8")
        ).hexdigest()[:16]
        bases = sorted({images[index].group_basis for index in indices})
        group_basis = ";".join(bases)
        if len(indices) > 1:
            group_basis += ";merged_by_sequence_or_duplicate_leakage_guard"
        for index in indices:
            updated[index] = replace(
                images[index],
                source_group_id=f"{dataset_prefix}:leakage-group-{digest}",
                group_basis=group_basis,
            )
    return updated, {
        "base_source_groups": len(group_first),
        "conservative_leakage_groups": len(component_items),
        "exact_duplicate_merge_edges": exact_edges,
        "near_duplicate_merge_edges": near_edges,
    }


def _image_summary(images: list[InspectedImage]) -> dict[str, Any]:
    readable = [image for image in images if image.technical_status == "READABLE"]
    dimensions = [(image.width, image.height) for image in readable]
    return {
        "image_files": len(images),
        "readable_images": len(readable),
        "unreadable_images": len(images) - len(readable),
        "formats": dict(
            sorted(Counter(image.decoded_format for image in readable).items())
        ),
        "minimum_width": min((width for width, _ in dimensions), default=None),
        "maximum_width": max((width for width, _ in dimensions), default=None),
        "minimum_height": min((height for _, height in dimensions), default=None),
        "maximum_height": max((height for _, height in dimensions), default=None),
    }


def _accident_group(filename: str) -> str:
    stem = PurePosixPath(filename).stem
    source_stem = stem.split(".rf.", maxsplit=1)[0]
    return f"accident-detection-9k:{source_stem.casefold()}"


def _parse_yolo_accident_label(data: bytes) -> tuple[str, int]:
    try:
        text = data.decode("utf-8-sig")
    except UnicodeDecodeError:
        return "INVALID_ENCODING", 0
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if not lines:
        return "EMPTY", 0
    for line in lines:
        tokens = line.split()
        if len(tokens) != 5 or tokens[0] != "0":
            return "INVALID_YOLO_ACCIDENT_CLASS", 0
        try:
            x_center, y_center, width, height = map(float, tokens[1:])
        except ValueError:
            return "INVALID_YOLO_NUMBER", 0
        if not (
            0 <= x_center <= 1
            and 0 <= y_center <= 1
            and 0 < width <= 1
            and 0 < height <= 1
        ):
            return "INVALID_YOLO_BOUNDS", 0
    return "VALID_ACCIDENT_ANNOTATION", len(lines)


def inspect_accident_detection_archive(
    archive_path: Path,
) -> tuple[dict[str, Any], list[dict[str, str]]]:
    if not archive_path.is_file():
        raise SourceInspectionError(
            f"AccidentDetection-9k archive is missing: {archive_path}"
        )

    images: list[InspectedImage] = []
    split_counts: Counter[str] = Counter()
    label_split_counts: Counter[str] = Counter()
    annotation_statuses: Counter[str] = Counter()
    used_label_items: set[str] = set()
    with zipfile.ZipFile(archive_path) as archive:
        members = [member for member in archive.infolist() if not member.is_dir()]
        labels = {
            _normalise_member_name(member.filename): member
            for member in members
            if PurePosixPath(member.filename).suffix.lower() == ".txt"
            and "/labels/" in _normalise_member_name(member.filename)
        }
        for label_item in labels:
            label_path = PurePosixPath(label_item)
            try:
                label_split = label_path.parts[label_path.parts.index("Dataset") + 1]
            except (ValueError, IndexError):
                label_split = "unknown"
            normalised_split = {"valid": "validation"}.get(label_split, label_split)
            label_split_counts[normalised_split] += 1
        image_members = [
            member
            for member in members
            if PurePosixPath(member.filename).suffix.lower() in SUPPORTED_IMAGE_SUFFIXES
            and "/images/" in _normalise_member_name(member.filename)
        ]
        for member in sorted(image_members, key=lambda item: item.filename):
            source_item = _normalise_member_name(member.filename)
            path = PurePosixPath(source_item)
            try:
                publisher_split = path.parts[path.parts.index("Dataset") + 1]
            except (ValueError, IndexError):
                publisher_split = "unknown"
            publisher_split = {"valid": "validation"}.get(
                publisher_split, publisher_split
            )
            split_counts[publisher_split] += 1
            label_item = source_item.replace("/images/", "/labels/")
            label_item = str(PurePosixPath(label_item).with_suffix(".txt"))
            label_member = labels.get(label_item)
            if label_member is None:
                annotation_status, annotation_count = "MISSING", 0
            else:
                used_label_items.add(label_item)
                annotation_status, annotation_count = _parse_yolo_accident_label(
                    archive.read(label_member)
                )
            annotation_statuses[annotation_status] += 1
            image_bytes = archive.read(member)
            digest = _sha256_bytes(image_bytes)
            try:
                probe = probe_image_bytes(image_bytes)
                technical_status = "READABLE"
                width, height = probe.width, probe.height
                image_format, perceptual_hash = (
                    probe.image_format,
                    probe.perceptual_hash,
                )
            except ImageDecodeError:
                technical_status = "UNREADABLE"
                width = height = 0
                image_format = perceptual_hash = ""
            images.append(
                InspectedImage(
                    source_item=source_item,
                    source_filename=path.name,
                    publisher_split=publisher_split,
                    source_group_id=_accident_group(path.name),
                    group_basis="roboflow_pre_augmentation_filename",
                    annotation_status=annotation_status,
                    annotation_count=annotation_count,
                    technical_status=technical_status,
                    rights_status="REVIEW_REQUIRED",
                    sha256=digest,
                    perceptual_hash=perceptual_hash,
                    width=width,
                    height=height,
                    decoded_format=image_format,
                )
            )

    images, grouping_summary = _apply_conservative_leakage_groups(
        images, "accident-detection-9k"
    )
    valid_candidates = sum(
        image.technical_status == "READABLE"
        and image.annotation_status == "VALID_ACCIDENT_ANNOTATION"
        for image in images
    )
    summary = {
        "dataset_id": "accident-detection-9k-mendeley",
        "dataset_version": "mendeley-v2-doi-10.17632/4x5my8gbcs.2",
        "archive_path": archive_path.as_posix(),
        "archive_bytes": archive_path.stat().st_size,
        "archive_sha256": sha256_file(archive_path),
        "archive_entries": len(members),
        **_image_summary(images),
        "publisher_split_image_counts": dict(sorted(split_counts.items())),
        "publisher_split_label_file_counts": dict(sorted(label_split_counts.items())),
        "label_files": len(labels),
        "orphan_label_files": len(set(labels) - used_label_items),
        "bounding_box_annotations": sum(image.annotation_count for image in images),
        "annotation_status_counts": dict(sorted(annotation_statuses.items())),
        "publisher_annotated_technical_candidates": valid_candidates,
        "semantically_reviewed_accident_images": 0,
        "rights_approved_accident_images": 0,
        "class_names": ["Accident"],
        "grouping": grouping_summary,
        "duplicate_analysis": _duplicate_summary(images),
        "training_blockers": [
            "Underlying images were discovered through Google image searches; "
            "per-image copyright provenance is not established by the record-level "
            "CC BY 4.0 declaration.",
            "Publisher accident boxes are candidate evidence, not an IRIS "
            "semantic review of every still image.",
            "Publisher train/validation/test partitions are not accepted until "
            "source grouping and duplicate leakage are resolved.",
        ],
    }
    rows = [
        _review_row(
            image,
            "accident-detection-9k-mendeley",
            "mendeley-v2-doi-10.17632/4x5my8gbcs.2",
        )
        for image in images
    ]
    return summary, rows


def load_mendeley_inventory(inventory_root: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for path in sorted(inventory_root.glob("*.page*.json")):
        payload = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(payload, list):
            raise SourceInspectionError(f"Inventory page is not a list: {path}")
        group = path.name.split(".page", maxsplit=1)[0]
        for item in payload:
            if not isinstance(item, dict):
                raise SourceInspectionError(f"Invalid inventory item in {path}")
            records.append({**item, "iris_inventory_group": group})
    return records


def _dats_group(filename: str, member_name: str) -> tuple[str, str]:
    stem = PurePosixPath(filename).stem
    timestamp_match = re.fullmatch(r"(\d{13})", stem)
    if timestamp_match:
        day_bucket = int(timestamp_match.group(1)) // 86_400_000
        return (
            f"dats-2022:timestamp-day-{day_bucket}",
            "epoch_millisecond_filename_grouped_conservatively_by_utc_day",
        )
    camera_match = re.match(r"(?i)IMG[_-](\d{8})[_-]\d{6}", stem)
    if camera_match:
        return (
            f"dats-2022:camera-day-{camera_match.group(1)}",
            "camera_timestamp_filename_grouped_conservatively_by_capture_day",
        )
    if re.fullmatch(r"(?i)D[_-]\d+", stem):
        return (
            "dats-2022:d-series-unresolved",
            "publisher_d_series_without_recoverable_sequence_identity",
        )
    numbered_copy = re.fullmatch(r"(.+?)\s*\(\d+\)", stem)
    if numbered_copy:
        return (
            f"dats-2022:numbered-{numbered_copy.group(1).casefold()}",
            "numbered_filename_family",
        )
    parent = PurePosixPath(member_name).parent.as_posix().casefold()
    return (
        f"dats-2022:unresolved:{parent}",
        "directory_only_sequence_identity_unresolved",
    )


def _dats_annotation_classes(
    suffix: str, data: bytes
) -> tuple[set[str], bool]:
    try:
        if suffix == ".json":
            payload = json.loads(data.decode("utf-8-sig"))
            items = payload if isinstance(payload, list) else [payload]
            classes = {
                annotation["label"]
                for item in items
                if isinstance(item, dict)
                for annotation in item.get("annotations", [])
                if isinstance(annotation, dict) and annotation.get("label")
            }
            return classes, True
        if suffix == ".xml":
            root = element_tree.fromstring(data)
            return {
                name.text.strip()
                for name in root.findall(".//object/name")
                if name.text and name.text.strip()
            }, True
        if suffix == ".txt":
            for line in data.decode("utf-8-sig").splitlines():
                if line.strip() and not re.fullmatch(
                    r"\d+\s+[-+0-9.eE]+\s+[-+0-9.eE]+\s+[-+0-9.eE]+\s+[-+0-9.eE]+",
                    line.strip(),
                ):
                    return set(), False
            return set(), True
    except (
        UnicodeDecodeError,
        json.JSONDecodeError,
        element_tree.ParseError,
        TypeError,
    ):
        return set(), False
    return set(), True


def inspect_dats_archive(
    archive_path: Path,
    inventory_root: Path,
) -> tuple[dict[str, Any], list[dict[str, str]]]:
    if not archive_path.is_file():
        raise SourceInspectionError(f"DATS_2022 archive is missing: {archive_path}")
    inventory = load_mendeley_inventory(inventory_root)
    expected_hashes = Counter(
        str(item.get("content_details", {}).get("sha256_hash", ""))
        for item in inventory
    )
    expected_hashes.pop("", None)

    images: list[InspectedImage] = []
    actual_hashes: Counter[str] = Counter()
    member_suffixes: Counter[str] = Counter()
    annotation_classes: dict[str, set[str]] = defaultdict(set)
    annotation_parse_failures: Counter[str] = Counter()
    annotation_files: Counter[str] = Counter()

    with zipfile.ZipFile(archive_path) as archive:
        members = [member for member in archive.infolist() if not member.is_dir()]
        for member in sorted(members, key=lambda item: item.filename):
            source_item = _normalise_member_name(member.filename)
            path = PurePosixPath(source_item)
            suffix = path.suffix.lower()
            member_suffixes[suffix or "<none>"] += 1
            data = archive.read(member)
            digest = _sha256_bytes(data)
            actual_hashes[digest] += 1
            if suffix in {".json", ".xml", ".txt"}:
                annotation_files[suffix] += 1
                classes, parsed = _dats_annotation_classes(suffix, data)
                annotation_classes[suffix].update(classes)
                if not parsed:
                    annotation_parse_failures[suffix] += 1
            if suffix not in SUPPORTED_IMAGE_SUFFIXES:
                continue
            try:
                probe = probe_image_bytes(data)
                technical_status = "READABLE"
                width, height = probe.width, probe.height
                image_format, perceptual_hash = (
                    probe.image_format,
                    probe.perceptual_hash,
                )
            except ImageDecodeError:
                technical_status = "UNREADABLE"
                width = height = 0
                image_format = perceptual_hash = ""
            group_id, group_basis = _dats_group(path.name, source_item)
            images.append(
                InspectedImage(
                    source_item=source_item,
                    source_filename=path.name,
                    publisher_split="",
                    source_group_id=group_id,
                    group_basis=group_basis,
                    annotation_status="OBJECT_DETECTION_ONLY_NOT_ACCIDENT_LABEL",
                    annotation_count=0,
                    technical_status=technical_status,
                    rights_status="APPROVED",
                    sha256=digest,
                    perceptual_hash=perceptual_hash,
                    width=width,
                    height=height,
                    decoded_format=image_format,
                )
            )

    images, grouping_summary = _apply_conservative_leakage_groups(
        images, "dats-2022"
    )
    missing_hashes = expected_hashes - actual_hashes
    unexpected_hashes = actual_hashes - expected_hashes
    summary = {
        "dataset_id": "dats-2022-mendeley",
        "dataset_version": "mendeley-v2-doi-10.17632/nfc34n8svj.2",
        "archive_path": archive_path.as_posix(),
        "archive_bytes": archive_path.stat().st_size,
        "archive_sha256": sha256_file(archive_path),
        "archive_entries": len(members),
        "official_inventory_files": len(inventory),
        "official_inventory_bytes": sum(int(item.get("size", 0)) for item in inventory),
        "archive_content_matches_inventory_hash_multiset": not missing_hashes
        and not unexpected_hashes,
        "missing_inventory_file_instances": sum(missing_hashes.values()),
        "unexpected_archive_file_instances": sum(unexpected_hashes.values()),
        "member_suffix_counts": dict(sorted(member_suffixes.items())),
        **_image_summary(images),
        "candidate_normal_images_pending_semantic_review": sum(
            image.technical_status == "READABLE" for image in images
        ),
        "semantically_reviewed_non_accident_images": 0,
        "annotation_file_counts": dict(sorted(annotation_files.items())),
        "annotation_parse_failures": dict(sorted(annotation_parse_failures.items())),
        "object_detection_class_names_by_format": {
            suffix: sorted(names)
            for suffix, names in sorted(annotation_classes.items())
        },
        "grouping": grouping_summary,
        "duplicate_analysis": _duplicate_summary(images),
        "group_basis_counts": dict(
            sorted(Counter(image.group_basis for image in images).items())
        ),
        "training_blockers": [
            "DATS_2022 object annotations do not establish the non_accident label.",
            "Every candidate still requires IRIS semantic review; ambiguous and "
            "transition imagery must be excluded.",
            "Original video sequence identity is only partially recoverable from "
            "filenames, so conservative groups and near-duplicate review are "
            "required before splitting.",
        ],
    }
    rows = [
        _review_row(
            image,
            "dats-2022-mendeley",
            "mendeley-v2-doi-10.17632/nfc34n8svj.2",
        )
        for image in images
    ]
    return summary, rows


def write_source_inspection(
    path: Path,
    source_summaries: list[dict[str, Any]],
    cross_source_summary: dict[str, Any],
) -> None:
    payload = {
        "inspection_version": INSPECTION_VERSION,
        "near_duplicate_threshold_hamming_bits": NEAR_DUPLICATE_THRESHOLD,
        "sources": source_summaries,
        "cross_source_duplicate_analysis": cross_source_summary,
        "manifest_rows_added": 0,
        "training_eligible": False,
        "training_eligibility_reason": (
            "No item has completed required semantic review and the accident source "
            "still requires underlying-image rights review."
        ),
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    temporary.replace(path)


def apply_cross_source_leakage_groups(
    accident_rows: list[dict[str, str]], dats_rows: list[dict[str, str]]
) -> tuple[list[dict[str, str]], list[dict[str, str]], dict[str, Any]]:
    all_group_ids = sorted(
        {row["source_group_id"] for row in accident_rows + dats_rows}
    )
    parent = {group_id: group_id for group_id in all_group_ids}

    def find(group_id: str) -> str:
        while parent[group_id] != group_id:
            parent[group_id] = parent[parent[group_id]]
            group_id = parent[group_id]
        return group_id

    def union(left: str, right: str) -> None:
        left_root = find(left)
        right_root = find(right)
        if left_root != right_root:
            parent[right_root] = left_root

    exact_by_hash: dict[str, list[int]] = defaultdict(list)
    near_index = PerceptualHashIndex()
    for index, row in enumerate(accident_rows):
        exact_by_hash[row["sha256"]].append(index)
        if row["perceptual_hash"]:
            near_index.add(row["perceptual_hash"], index)

    exact_pairs = 0
    non_exact_near_pairs = 0
    examples: list[dict[str, Any]] = []
    for dats_row in dats_rows:
        matched_accident_indices: set[int] = set()
        for accident_index in exact_by_hash.get(dats_row["sha256"], []):
            exact_pairs += 1
            matched_accident_indices.add(accident_index)
            accident_row = accident_rows[accident_index]
            union(accident_row["source_group_id"], dats_row["source_group_id"])
            if len(examples) < 25:
                examples.append(
                    {
                        "relationship": "exact_sha256",
                        "accident_source_item": accident_row["source_item"],
                        "dats_source_item": dats_row["source_item"],
                        "hamming_distance": 0,
                    }
                )
        if not dats_row["perceptual_hash"]:
            continue
        for accident_index, distance in near_index.query(
            dats_row["perceptual_hash"], NEAR_DUPLICATE_THRESHOLD
        ):
            if accident_index in matched_accident_indices:
                continue
            accident_row = accident_rows[accident_index]
            non_exact_near_pairs += 1
            union(accident_row["source_group_id"], dats_row["source_group_id"])
            if len(examples) < 25:
                examples.append(
                    {
                        "relationship": "dhash_candidate",
                        "accident_source_item": accident_row["source_item"],
                        "dats_source_item": dats_row["source_item"],
                        "hamming_distance": distance,
                    }
                )

    component_groups: dict[str, list[str]] = defaultdict(list)
    for group_id in all_group_ids:
        component_groups[find(group_id)].append(group_id)
    cross_group_map: dict[str, str] = {}
    for group_ids in component_groups.values():
        has_accident = any(
            group_id.startswith("accident-detection-9k:") for group_id in group_ids
        )
        has_dats = any(group_id.startswith("dats-2022:") for group_id in group_ids)
        if not (has_accident and has_dats):
            continue
        digest = hashlib.sha256(
            "\n".join(sorted(group_ids)).encode("utf-8")
        ).hexdigest()[:16]
        for group_id in group_ids:
            cross_group_map[group_id] = f"cross-source:leakage-group-{digest}"

    def updated(rows: list[dict[str, str]]) -> list[dict[str, str]]:
        result: list[dict[str, str]] = []
        for row in rows:
            replacement = cross_group_map.get(row["source_group_id"])
            if replacement is None:
                result.append(row)
                continue
            result.append(
                {
                    **row,
                    "source_group_id": replacement,
                    "group_basis": (
                        row["group_basis"]
                        + ";cross_source_exact_or_dhash_leakage_guard"
                    ),
                }
            )
        return result

    return updated(accident_rows), updated(dats_rows), {
        "exact_duplicate_pairs": exact_pairs,
        "non_exact_near_duplicate_pairs": non_exact_near_pairs,
        "near_duplicate_threshold_hamming_bits": NEAR_DUPLICATE_THRESHOLD,
        "cross_source_leakage_groups": len(set(cross_group_map.values())),
        "examples": examples,
        "policy": (
            "Cross-source exact matches and dHash candidates are forced into one "
            "conservative group and require conflict review before labelling."
        ),
    }


def inspect_mendeley_sources(
    accident_archive: Path,
    dats_archive: Path,
    dats_inventory_root: Path,
    accident_review_output: Path,
    dats_review_output: Path,
    report_output: Path,
) -> dict[str, Any]:
    accident_summary, accident_rows = inspect_accident_detection_archive(
        accident_archive
    )
    dats_summary, dats_rows = inspect_dats_archive(
        dats_archive, dats_inventory_root
    )
    accident_rows, dats_rows, cross_source_summary = (
        apply_cross_source_leakage_groups(accident_rows, dats_rows)
    )
    update_review_inventory(accident_review_output, accident_rows)
    update_review_inventory(dats_review_output, dats_rows)
    write_source_inspection(
        report_output,
        [accident_summary, dats_summary],
        cross_source_summary,
    )
    return {
        "accident_images": len(accident_rows),
        "dats_images": len(dats_rows),
        "report": report_output.as_posix(),
    }
