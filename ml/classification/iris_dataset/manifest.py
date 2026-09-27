from __future__ import annotations

import csv
import json
from pathlib import Path
from typing import Any, Iterable, Mapping

MANIFEST_VERSION = "iris-classification-manifest-v1"
REGISTRY_VERSION = "iris-dataset-source-registry-v1"

MANIFEST_FIELDS = (
    "manifest_version",
    "item_id",
    "relative_path",
    "label",
    "split",
    "source_dataset_id",
    "source_dataset_version",
    "source_group_id",
    "source_event_id",
    "source_video_id",
    "source_frame_index",
    "source_timestamp_ms",
    "source_reference",
    "source_category",
    "label_basis",
    "license_status",
    "sha256",
    "perceptual_hash",
    "extraction_version",
    "width",
    "height",
    "day_night",
    "weather",
    "ego_involvement",
    "accident_category",
)


class DatasetConfigurationError(ValueError):
    """Raised when version-controlled dataset configuration is malformed."""


def load_json(path: Path) -> Any:
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError as error:
        raise DatasetConfigurationError(f"Required file is missing: {path}") from error
    except json.JSONDecodeError as error:
        raise DatasetConfigurationError(
            f"Invalid JSON in {path}: line {error.lineno}, column {error.colno}"
        ) from error


def load_manifest(path: Path) -> list[dict[str, str]]:
    try:
        handle = path.open("r", encoding="utf-8-sig", newline="")
    except FileNotFoundError as error:
        raise DatasetConfigurationError(f"Manifest is missing: {path}") from error

    with handle:
        reader = csv.DictReader(handle)
        actual_fields = tuple(reader.fieldnames or ())
        missing = [field for field in MANIFEST_FIELDS if field not in actual_fields]
        unexpected = [field for field in actual_fields if field not in MANIFEST_FIELDS]
        if missing or unexpected:
            raise DatasetConfigurationError(
                "Manifest header does not match v1 schema; "
                f"missing={missing}, unexpected={unexpected}"
            )
        return [
            {field: (row.get(field) or "").strip() for field in MANIFEST_FIELDS}
            for row in reader
        ]


def write_manifest(path: Path, rows: Iterable[Mapping[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = path.with_suffix(path.suffix + ".tmp")
    with temporary_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=MANIFEST_FIELDS, lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow({field: row.get(field, "") for field in MANIFEST_FIELDS})
    temporary_path.replace(path)


def load_source_registry(path: Path) -> dict[str, dict[str, Any]]:
    payload = load_json(path)
    if not isinstance(payload, dict):
        raise DatasetConfigurationError("Source registry root must be an object")
    if payload.get("schema_version") != REGISTRY_VERSION:
        raise DatasetConfigurationError(
            f"Unsupported source registry version: {payload.get('schema_version')!r}"
        )
    sources = payload.get("sources")
    if not isinstance(sources, list):
        raise DatasetConfigurationError("Source registry 'sources' must be a list")

    registry: dict[str, dict[str, Any]] = {}
    required = {
        "dataset_id",
        "official_name",
        "official_reference",
        "dataset_version",
        "usage_status",
        "redistribution_status",
        "derived_data_status",
        "acquisition_method",
        "local_raw_path",
        "task_suitability",
    }
    for index, source in enumerate(sources):
        if not isinstance(source, dict):
            raise DatasetConfigurationError(
                f"Source registry entry {index} must be an object"
            )
        missing = sorted(required - source.keys())
        if missing:
            raise DatasetConfigurationError(
                f"Source registry entry {index} is missing: {missing}"
            )
        dataset_id = source["dataset_id"]
        if not isinstance(dataset_id, str) or not dataset_id.strip():
            raise DatasetConfigurationError(
                f"Source registry entry {index} has an invalid dataset_id"
            )
        if dataset_id in registry:
            raise DatasetConfigurationError(
                f"Duplicate source registry dataset_id: {dataset_id}"
            )
        registry[dataset_id] = source
    return registry
