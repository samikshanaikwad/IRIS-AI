from __future__ import annotations

import json
import re
import zipfile
from collections import Counter
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

from .image_tools import sha256_file
from .manifest import DatasetConfigurationError

OFFICIAL_REPOSITORY = "https://github.com/MoonBlvd/Detection-of-Traffic-Anomaly"
OFFICIAL_COMMIT = "f8f603b8c06a946bc314752947ed480a4f33f82a"
EXPECTED_METADATA_HASHES = {
    "DoTA_annotations.zip": "56209f87398cbf47b9eeee4b516461e71cd3f97f9dd8c4432773315db307ff15",
    "metadata_train.json": "eceb50ab8237c1fd27e1a0a99cc724a7fa4300aff0bcada99eace2c70bb22efd",
    "metadata_val.json": "d273974886f9e68113dad6fdbb6217ac4476c47efd7aab878ac37bf3579b895d",
    "DoTA_urls.txt": "25ce01a4ddc398f0225653596d8a15171c26a6f5625317e8064157c8918c844d",
}
CLIP_SUFFIX = re.compile(r"^(?P<video>.+)_(?P<start>\d{6})$")


@dataclass(frozen=True)
class DotaInspection:
    official_commit: str
    annotation_count: int
    ignored_annotation_count: int
    metadata_train_count: int
    metadata_validation_count: int
    unique_source_video_count: int
    official_split_overlap_source_videos: int
    active_url_count: int
    category_counts: dict[str, int]
    metadata_hashes: dict[str, str]
    frame_event_directories_found: int | None
    frame_event_directories_missing: int | None
    errors: tuple[str, ...]
    warnings: tuple[str, ...]

    def as_json(self) -> dict[str, Any]:
        return asdict(self)


def source_video_id(source_event_id: str) -> str:
    if (
        not source_event_id
        or source_event_id in {".", ".."}
        or "/" in source_event_id
        or "\\" in source_event_id
    ):
        raise DatasetConfigurationError(
            f"Unsafe DoTA source event ID: {source_event_id!r}"
        )
    match = CLIP_SUFFIX.fullmatch(source_event_id)
    if match is None:
        raise DatasetConfigurationError(
            f"DoTA event ID does not end in a six-digit clip start: {source_event_id!r}"
        )
    return match.group("video")


def category_name(annotation: dict[str, Any]) -> str:
    viewpoint = "ego" if annotation.get("ego_involve") is True else "other"
    return f"{viewpoint}: {annotation.get('accident_name', '')}"


def _load_metadata(path: Path) -> dict[str, dict[str, Any]]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise DatasetConfigurationError(f"DoTA metadata file is missing: {path}") from error
    except json.JSONDecodeError as error:
        raise DatasetConfigurationError(f"Invalid DoTA metadata JSON: {path}") from error
    if not isinstance(payload, dict):
        raise DatasetConfigurationError(f"DoTA metadata root must be an object: {path}")
    return payload


def inspect_dota_metadata(
    metadata_root: Path, frames_root: Path | None = None
) -> DotaInspection:
    errors: list[str] = []
    warnings: list[str] = []
    actual_hashes: dict[str, str] = {}
    for filename, expected in EXPECTED_METADATA_HASHES.items():
        path = metadata_root / filename
        if not path.is_file():
            errors.append(f"Missing official metadata file: {filename}")
            continue
        actual = sha256_file(path)
        actual_hashes[filename] = actual
        if actual != expected:
            errors.append(
                f"Checksum mismatch for {filename}; expected official commit {OFFICIAL_COMMIT}"
            )

    train_path = metadata_root / "metadata_train.json"
    validation_path = metadata_root / "metadata_val.json"
    if not train_path.is_file() or not validation_path.is_file():
        return DotaInspection(
            official_commit=OFFICIAL_COMMIT,
            annotation_count=0,
            ignored_annotation_count=0,
            metadata_train_count=0,
            metadata_validation_count=0,
            unique_source_video_count=0,
            official_split_overlap_source_videos=0,
            active_url_count=0,
            category_counts={},
            metadata_hashes=actual_hashes,
            frame_event_directories_found=None,
            frame_event_directories_missing=None,
            errors=tuple(errors),
            warnings=tuple(warnings),
        )

    train = _load_metadata(train_path)
    validation = _load_metadata(validation_path)
    all_metadata = {**train, **validation}
    if len(all_metadata) != len(train) + len(validation):
        errors.append("A DoTA clip ID occurs in both official metadata files")

    train_sources: set[str] = set()
    validation_sources: set[str] = set()
    category_counts: Counter[str] = Counter()
    for subset, records, source_set in (
        ("train", train, train_sources),
        ("validation", validation, validation_sources),
    ):
        for event_id, record in records.items():
            try:
                source_set.add(source_video_id(event_id))
            except DatasetConfigurationError as error:
                errors.append(str(error))
            if not isinstance(record, dict):
                errors.append(f"Metadata record is not an object: {event_id}")
                continue
            category = record.get("anomaly_class")
            if not isinstance(category, str) or not category:
                errors.append(f"Missing anomaly_class: {event_id}")
            else:
                category_counts[category] += 1
            for field in (
                "video_start",
                "video_end",
                "anomaly_start",
                "anomaly_end",
                "num_frames",
            ):
                if not isinstance(record.get(field), int):
                    errors.append(f"Malformed {field} for {event_id} in {subset}")

    annotation_count = 0
    ignored_annotation_count = 0
    annotation_zip = metadata_root / "DoTA_annotations.zip"
    if annotation_zip.is_file():
        try:
            with zipfile.ZipFile(annotation_zip) as archive:
                annotation_names = [
                    name
                    for name in archive.namelist()
                    if name.startswith("annotations/") and name.endswith(".json")
                ]
                annotation_count = len(annotation_names)
                for name in annotation_names:
                    try:
                        annotation = json.loads(archive.read(name))
                    except (UnicodeDecodeError, json.JSONDecodeError):
                        errors.append(f"Malformed annotation JSON in archive: {name}")
                        continue
                    if annotation.get("ignore") is True:
                        ignored_annotation_count += 1
        except zipfile.BadZipFile:
            errors.append("DoTA_annotations.zip is not a valid ZIP archive")

    active_url_count = 0
    url_path = metadata_root / "DoTA_urls.txt"
    if url_path.is_file():
        active_url_count = sum(
            bool(line.strip()) for line in url_path.read_text(encoding="utf-8").splitlines()
        )

    found: int | None = None
    missing: int | None = None
    if frames_root is not None:
        frames_directory = frames_root / "frames"
        found = 0
        missing = 0
        for event_id in all_metadata:
            images = frames_directory / event_id / "images"
            if images.is_dir():
                found += 1
            else:
                missing += 1
        if missing:
            errors.append(f"Official frame archive is missing {missing} event directories")

    overlap = train_sources & validation_sources
    if overlap:
        warnings.append(
            f"Official clip split leaks {len(overlap)} original source videos; "
            "IRIS must create a source-video-grouped split"
        )
    if annotation_count and annotation_count != len(all_metadata):
        errors.append(
            f"Annotation count {annotation_count} differs from metadata count {len(all_metadata)}"
        )

    return DotaInspection(
        official_commit=OFFICIAL_COMMIT,
        annotation_count=annotation_count,
        ignored_annotation_count=ignored_annotation_count,
        metadata_train_count=len(train),
        metadata_validation_count=len(validation),
        unique_source_video_count=len(train_sources | validation_sources),
        official_split_overlap_source_videos=len(overlap),
        active_url_count=active_url_count,
        category_counts=dict(sorted(category_counts.items())),
        metadata_hashes=actual_hashes,
        frame_event_directories_found=found,
        frame_event_directories_missing=missing,
        errors=tuple(errors),
        warnings=tuple(warnings),
    )
