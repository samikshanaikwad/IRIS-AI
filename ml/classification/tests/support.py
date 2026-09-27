from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from PIL import Image

from iris_dataset.image_tools import probe_image, sha256_file
from iris_dataset.manifest import MANIFEST_VERSION, write_manifest

SOURCE_ID = "test-source"
SOURCE_VERSION = "test-source-v1"
EXTRACTION_VERSION = "test-extraction-v1"


def write_registry(path: Path, approved: bool = True) -> dict[str, Any]:
    status = "APPROVED" if approved else "REVIEW_REQUIRED"
    source = {
        "dataset_id": SOURCE_ID,
        "official_name": "Synthetic unit-test source",
        "official_reference": "test-only",
        "dataset_version": SOURCE_VERSION,
        "usage_status": status,
        "redistribution_status": status,
        "derived_data_status": status,
        "acquisition_method": "Generated inside temporary unit-test directory",
        "local_raw_path": "test-only",
        "task_suitability": "TEST_ONLY",
    }
    path.write_text(
        json.dumps(
            {
                "schema_version": "iris-dataset-source-registry-v1",
                "sources": [source],
            }
        ),
        encoding="utf-8",
    )
    return source


def create_image(
    path: Path,
    color: tuple[int, int, int] = (20, 40, 60),
    size: tuple[int, int] = (16, 12),
    image_format: str = "PNG",
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGB", size, color).save(path, format=image_format)


def manifest_row(
    data_root: Path,
    relative_path: str,
    *,
    item_id: str = "item-1",
    label: str = "accident",
    split: str = "train",
    group_id: str = "group-1",
    event_id: str = "event-1",
    video_id: str = "video-1",
    source_id: str = SOURCE_ID,
    source_version: str = SOURCE_VERSION,
    extraction_version: str = EXTRACTION_VERSION,
    license_status: str = "APPROVED",
) -> dict[str, str]:
    image_path = data_root / relative_path
    probe = probe_image(image_path)
    return {
        "manifest_version": MANIFEST_VERSION,
        "item_id": item_id,
        "relative_path": relative_path,
        "label": label,
        "split": split,
        "source_dataset_id": source_id,
        "source_dataset_version": source_version,
        "source_group_id": group_id,
        "source_event_id": event_id,
        "source_video_id": video_id,
        "source_frame_index": "0",
        "source_timestamp_ms": "0",
        "source_reference": "test-only",
        "source_category": "test-category",
        "label_basis": "synthetic_test_fixture",
        "license_status": license_status,
        "sha256": sha256_file(image_path),
        "perceptual_hash": probe.perceptual_hash,
        "extraction_version": extraction_version,
        "width": str(probe.width),
        "height": str(probe.height),
        "day_night": "unknown",
        "weather": "unknown",
        "ego_involvement": "unknown",
        "accident_category": "test-only",
    }


def write_rows(path: Path, rows: list[dict[str, str]]) -> None:
    write_manifest(path, rows)
