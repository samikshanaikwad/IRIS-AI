from __future__ import annotations

import re
from collections import defaultdict
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

from .duplicates import find_near_duplicate_pairs
from .image_tools import ImageDecodeError, ImageDependencyError, probe_image, sha256_file
from .manifest import MANIFEST_VERSION, load_manifest, load_source_registry

ALLOWED_LABELS = {"accident", "non_accident"}
ALLOWED_SPLITS = {"train", "validation", "test", "external_test"}
ALLOWED_LICENSE_STATUSES = {
    "APPROVED",
    "REVIEW_REQUIRED",
    "RESTRICTED",
    "PROHIBITED",
}
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
DHASH_PATTERN = re.compile(r"^[0-9a-f]{16}$")
SUPPORTED_SUFFIXES = {".jpg", ".jpeg", ".png"}

REQUIRED_TEXT_FIELDS = {
    "item_id",
    "relative_path",
    "source_dataset_id",
    "source_dataset_version",
    "source_group_id",
    "source_event_id",
    "label_basis",
    "license_status",
    "sha256",
    "perceptual_hash",
    "extraction_version",
    "width",
    "height",
}


@dataclass(frozen=True)
class ValidationIssue:
    severity: str
    code: str
    message: str
    item_ids: tuple[str, ...] = ()


@dataclass
class ValidationResult:
    rows: list[dict[str, str]]
    issues: list[ValidationIssue]
    computed_hashes: dict[str, str]
    computed_perceptual_hashes: dict[str, str]

    @property
    def error_count(self) -> int:
        return sum(issue.severity == "ERROR" for issue in self.issues)

    @property
    def warning_count(self) -> int:
        return sum(issue.severity == "WARNING" for issue in self.issues)

    @property
    def info_count(self) -> int:
        return sum(issue.severity == "INFO" for issue in self.issues)

    @property
    def training_eligible(self) -> bool:
        return bool(self.rows) and self.error_count == 0

    def as_json(self) -> dict[str, Any]:
        return {
            "item_count": len(self.rows),
            "training_eligible": self.training_eligible,
            "error_count": self.error_count,
            "warning_count": self.warning_count,
            "info_count": self.info_count,
            "issues": [asdict(issue) for issue in self.issues],
        }


def _parse_non_negative_integer(
    value: str, field: str, item_id: str, issues: list[ValidationIssue]
) -> int | None:
    if value == "":
        return None
    try:
        parsed = int(value)
    except ValueError:
        issues.append(
            ValidationIssue(
                "ERROR",
                "MALFORMED_INTEGER",
                f"{field} must be an integer, received {value!r}",
                (item_id,),
            )
        )
        return None
    if parsed < 0:
        issues.append(
            ValidationIssue(
                "ERROR",
                "NEGATIVE_INTEGER",
                f"{field} must be non-negative, received {parsed}",
                (item_id,),
            )
        )
        return None
    return parsed


def _safe_data_path(
    data_root: Path,
    relative_path: str,
    item_id: str,
    issues: list[ValidationIssue],
) -> Path | None:
    candidate_relative = Path(relative_path)
    if candidate_relative.is_absolute():
        issues.append(
            ValidationIssue(
                "ERROR",
                "UNSAFE_PATH",
                "relative_path must not be absolute",
                (item_id,),
            )
        )
        return None
    root = data_root.resolve()
    candidate = (root / candidate_relative).resolve()
    if not candidate.is_relative_to(root):
        issues.append(
            ValidationIssue(
                "ERROR",
                "UNSAFE_PATH",
                "relative_path escapes the configured derived-data root",
                (item_id,),
            )
        )
        return None
    return candidate


def validate_dataset(
    manifest_path: Path,
    source_registry_path: Path,
    data_root: Path,
    known_extraction_versions: set[str],
    near_duplicate_threshold: int = 4,
) -> ValidationResult:
    rows = load_manifest(manifest_path)
    registry = load_source_registry(source_registry_path)
    issues: list[ValidationIssue] = []
    computed_hashes: dict[str, str] = {}
    computed_perceptual_hashes: dict[str, str] = {}
    item_ids: dict[str, int] = {}
    relative_paths: dict[str, int] = {}
    group_splits: dict[str, set[str]] = defaultdict(set)
    group_items: dict[str, list[str]] = defaultdict(list)
    sha_items: dict[str, list[int]] = defaultdict(list)
    image_dhashes: list[tuple[int, str]] = []

    if not rows:
        issues.append(
            ValidationIssue(
                "INFO",
                "EMPTY_DATASET",
                "No real classification dataset items are present in the manifest",
            )
        )

    for index, row in enumerate(rows):
        item_id = row["item_id"] or f"<row-{index + 2}>"
        if row["manifest_version"] != MANIFEST_VERSION:
            issues.append(
                ValidationIssue(
                    "ERROR",
                    "INVALID_MANIFEST_VERSION",
                    f"Expected {MANIFEST_VERSION!r}",
                    (item_id,),
                )
            )

        for field in sorted(REQUIRED_TEXT_FIELDS):
            if not row[field]:
                issues.append(
                    ValidationIssue(
                        "ERROR",
                        "MISSING_REQUIRED_FIELD",
                        f"Required field is empty: {field}",
                        (item_id,),
                    )
                )

        if row["label"] not in ALLOWED_LABELS:
            issues.append(
                ValidationIssue(
                    "ERROR",
                    "INVALID_LABEL",
                    f"Unknown label: {row['label']!r}",
                    (item_id,),
                )
            )
        if row["split"] not in ALLOWED_SPLITS:
            issues.append(
                ValidationIssue(
                    "ERROR",
                    "INVALID_SPLIT",
                    f"Unknown split: {row['split']!r}",
                    (item_id,),
                )
            )
        if row["license_status"] not in ALLOWED_LICENSE_STATUSES:
            issues.append(
                ValidationIssue(
                    "ERROR",
                    "INVALID_LICENSE_STATUS",
                    f"Unknown license status: {row['license_status']!r}",
                    (item_id,),
                )
            )
        elif row["license_status"] != "APPROVED":
            issues.append(
                ValidationIssue(
                    "ERROR",
                    "ITEM_USAGE_NOT_APPROVED",
                    f"Item license status is {row['license_status']}",
                    (item_id,),
                )
            )

        if row["item_id"]:
            prior = item_ids.get(row["item_id"])
            if prior is not None:
                issues.append(
                    ValidationIssue(
                        "ERROR",
                        "DUPLICATE_ITEM_ID",
                        f"item_id also occurs on row {prior + 2}",
                        (item_id,),
                    )
                )
            else:
                item_ids[row["item_id"]] = index

        if row["relative_path"]:
            path_key = row["relative_path"].replace("\\", "/").casefold()
            prior = relative_paths.get(path_key)
            if prior is not None:
                issues.append(
                    ValidationIssue(
                        "ERROR",
                        "DUPLICATE_RELATIVE_PATH",
                        f"relative_path also occurs on row {prior + 2}",
                        (item_id,),
                    )
                )
            else:
                relative_paths[path_key] = index

        source = registry.get(row["source_dataset_id"])
        if source is None:
            issues.append(
                ValidationIssue(
                    "ERROR",
                    "MISSING_SOURCE_REGISTRY",
                    f"No source registry entry for {row['source_dataset_id']!r}",
                    (item_id,),
                )
            )
        else:
            if source.get("usage_status") != "APPROVED":
                issues.append(
                    ValidationIssue(
                        "ERROR",
                        "SOURCE_USAGE_NOT_APPROVED",
                        f"Source usage status is {source.get('usage_status')!r}",
                        (item_id,),
                    )
                )
            if source.get("derived_data_status") != "APPROVED":
                issues.append(
                    ValidationIssue(
                        "ERROR",
                        "DERIVED_USE_NOT_APPROVED",
                        "Source does not have approved derived-data status",
                        (item_id,),
                    )
                )
            if row["source_dataset_version"] != source.get("dataset_version"):
                issues.append(
                    ValidationIssue(
                        "ERROR",
                        "SOURCE_VERSION_MISMATCH",
                        "Manifest source version differs from the source registry",
                        (item_id,),
                    )
                )

        if row["extraction_version"] not in known_extraction_versions:
            issues.append(
                ValidationIssue(
                    "ERROR",
                    "UNKNOWN_EXTRACTION_VERSION",
                    f"Unknown extraction version: {row['extraction_version']!r}",
                    (item_id,),
                )
            )

        frame_index = _parse_non_negative_integer(
            row["source_frame_index"], "source_frame_index", item_id, issues
        )
        _parse_non_negative_integer(
            row["source_timestamp_ms"], "source_timestamp_ms", item_id, issues
        )
        width = _parse_non_negative_integer(row["width"], "width", item_id, issues)
        height = _parse_non_negative_integer(row["height"], "height", item_id, issues)
        if width == 0 or height == 0:
            issues.append(
                ValidationIssue(
                    "ERROR",
                    "INVALID_DIMENSIONS",
                    "Image width and height must be greater than zero",
                    (item_id,),
                )
            )
        if row["source_video_id"] and frame_index is None:
            issues.append(
                ValidationIssue(
                    "ERROR",
                    "MISSING_VIDEO_FRAME_INDEX",
                    "Video-derived records require source_frame_index",
                    (item_id,),
                )
            )

        if row["source_group_id"] and row["split"] in ALLOWED_SPLITS:
            group_splits[row["source_group_id"]].add(row["split"])
            group_items[row["source_group_id"]].append(item_id)

        if row["sha256"] and not SHA256_PATTERN.fullmatch(row["sha256"]):
            issues.append(
                ValidationIssue(
                    "ERROR",
                    "INVALID_SHA256",
                    "sha256 must be 64 lowercase hexadecimal characters",
                    (item_id,),
                )
            )
        elif row["sha256"]:
            sha_items[row["sha256"]].append(index)

        if row["perceptual_hash"] and not DHASH_PATTERN.fullmatch(
            row["perceptual_hash"]
        ):
            issues.append(
                ValidationIssue(
                    "ERROR",
                    "INVALID_PERCEPTUAL_HASH",
                    "perceptual_hash must be a 64-bit lowercase hexadecimal dHash",
                    (item_id,),
                )
            )

        image_path = _safe_data_path(
            data_root, row["relative_path"], item_id, issues
        )
        if image_path is None:
            continue
        if image_path.suffix.lower() not in SUPPORTED_SUFFIXES:
            issues.append(
                ValidationIssue(
                    "ERROR",
                    "UNSUPPORTED_IMAGE_EXTENSION",
                    f"Unsupported image extension: {image_path.suffix}",
                    (item_id,),
                )
            )
            continue
        if not image_path.is_file():
            issues.append(
                ValidationIssue(
                    "ERROR",
                    "MISSING_FILE",
                    f"Image file is missing: {row['relative_path']}",
                    (item_id,),
                )
            )
            continue
        if image_path.stat().st_size == 0:
            issues.append(
                ValidationIssue(
                    "ERROR",
                    "ZERO_BYTE_FILE",
                    f"Image file is empty: {row['relative_path']}",
                    (item_id,),
                )
            )
            continue

        actual_sha256 = sha256_file(image_path)
        computed_hashes[item_id] = actual_sha256
        if row["sha256"] != actual_sha256:
            issues.append(
                ValidationIssue(
                    "ERROR",
                    "HASH_MISMATCH",
                    "Stored SHA-256 does not match the image bytes",
                    (item_id,),
                )
            )
        try:
            probe = probe_image(image_path)
        except ImageDependencyError:
            raise
        except ImageDecodeError as error:
            issues.append(
                ValidationIssue(
                    "ERROR",
                    "IMAGE_DECODE_FAILURE",
                    f"Image cannot be decoded: {error}",
                    (item_id,),
                )
            )
            continue
        computed_perceptual_hashes[item_id] = probe.perceptual_hash
        image_dhashes.append((index, probe.perceptual_hash))
        if row["perceptual_hash"] != probe.perceptual_hash:
            issues.append(
                ValidationIssue(
                    "ERROR",
                    "PERCEPTUAL_HASH_MISMATCH",
                    "Stored perceptual hash does not match the decoded image",
                    (item_id,),
                )
            )
        if width is not None and height is not None:
            if width != probe.width or height != probe.height:
                issues.append(
                    ValidationIssue(
                        "ERROR",
                        "DIMENSION_MISMATCH",
                        f"Manifest dimensions {width}x{height} differ from "
                        f"decoded dimensions {probe.width}x{probe.height}",
                        (item_id,),
                    )
                )

    for group_id, splits in sorted(group_splits.items()):
        if len(splits) > 1:
            issues.append(
                ValidationIssue(
                    "ERROR",
                    "SOURCE_GROUP_LEAKAGE",
                    f"Source group {group_id!r} occurs in splits {sorted(splits)}",
                    tuple(group_items[group_id]),
                )
            )

    for digest, indices in sorted(sha_items.items()):
        if len(indices) < 2:
            continue
        duplicate_rows = [rows[index] for index in indices]
        duplicate_ids = tuple(row["item_id"] for row in duplicate_rows)
        splits = {row["split"] for row in duplicate_rows}
        code = (
            "CROSS_SPLIT_EXACT_DUPLICATE"
            if len(splits) > 1
            else "EXACT_DUPLICATE_CONTENT"
        )
        issues.append(
            ValidationIssue(
                "ERROR",
                code,
                f"SHA-256 {digest} is shared by {len(indices)} records",
                duplicate_ids,
            )
        )

    for left_index, right_index, distance in find_near_duplicate_pairs(
        image_dhashes, near_duplicate_threshold
    ):
        left = rows[left_index]
        right = rows[right_index]
        if left["sha256"] == right["sha256"]:
            continue
        cross_split = left["split"] != right["split"]
        issues.append(
            ValidationIssue(
                "ERROR" if cross_split else "WARNING",
                (
                    "CROSS_SPLIT_NEAR_DUPLICATE"
                    if cross_split
                    else "NEAR_DUPLICATE_CANDIDATE"
                ),
                f"dHash distance {distance} requires human duplicate review",
                (left["item_id"], right["item_id"]),
            )
        )

    return ValidationResult(
        rows=rows,
        issues=issues,
        computed_hashes=computed_hashes,
        computed_perceptual_hashes=computed_perceptual_hashes,
    )
