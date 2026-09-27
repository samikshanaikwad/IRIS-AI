from __future__ import annotations

import csv
import json
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .dota import OFFICIAL_REPOSITORY, category_name, source_video_id
from .image_tools import probe_image, sha256_file
from .manifest import MANIFEST_VERSION, DatasetConfigurationError, load_json

VISIBLE_WINDOW_FIELDS = (
    "review_version",
    "source_event_id",
    "visible_start_frame",
    "visible_end_frame",
    "reviewer",
    "reviewed_at",
    "rationale",
)

NORMAL_WINDOW_FIELDS = (
    "review_version",
    "source_event_id",
    "normal_start_frame",
    "normal_end_frame",
    "reviewer",
    "reviewed_at",
    "rationale",
)


@dataclass(frozen=True)
class ExtractionResult:
    rows: tuple[dict[str, str], ...]
    warnings: tuple[str, ...]


def load_visible_windows(path: Path) -> dict[str, dict[str, str]]:
    try:
        handle = path.open("r", encoding="utf-8-sig", newline="")
    except FileNotFoundError as error:
        raise DatasetConfigurationError(
            f"Visible-collision review file is missing: {path}"
        ) from error
    with handle:
        reader = csv.DictReader(handle)
        if tuple(reader.fieldnames or ()) != VISIBLE_WINDOW_FIELDS:
            raise DatasetConfigurationError(
                "Visible-window CSV header does not match v1 schema"
            )
        windows: dict[str, dict[str, str]] = {}
        for row_number, row in enumerate(reader, start=2):
            normalized = {
                field: (row.get(field) or "").strip() for field in VISIBLE_WINDOW_FIELDS
            }
            event_id = normalized["source_event_id"]
            if not event_id:
                raise DatasetConfigurationError(
                    f"Visible-window row {row_number} has no source_event_id"
                )
            if event_id in windows:
                raise DatasetConfigurationError(
                    f"Duplicate visible-window source_event_id: {event_id}"
                )
            for field in ("review_version", "reviewer", "reviewed_at", "rationale"):
                if not normalized[field]:
                    raise DatasetConfigurationError(
                        f"Visible-window row {row_number} has no {field}"
                    )
            try:
                start = int(normalized["visible_start_frame"])
                end = int(normalized["visible_end_frame"])
            except ValueError as error:
                raise DatasetConfigurationError(
                    f"Visible-window row {row_number} has malformed frame bounds"
                ) from error
            if start < 0 or end < start:
                raise DatasetConfigurationError(
                    f"Visible-window row {row_number} has invalid frame bounds"
                )
            windows[event_id] = normalized
        return windows


def load_normal_windows(path: Path) -> dict[str, dict[str, str]]:
    try:
        handle = path.open("r", encoding="utf-8-sig", newline="")
    except FileNotFoundError as error:
        raise DatasetConfigurationError(
            f"Reviewed-normal-window file is missing: {path}"
        ) from error
    with handle:
        reader = csv.DictReader(handle)
        if tuple(reader.fieldnames or ()) != NORMAL_WINDOW_FIELDS:
            raise DatasetConfigurationError(
                "Normal-window CSV header does not match v1 schema"
            )
        windows: dict[str, dict[str, str]] = {}
        for row_number, row in enumerate(reader, start=2):
            normalized = {
                field: (row.get(field) or "").strip() for field in NORMAL_WINDOW_FIELDS
            }
            event_id = normalized["source_event_id"]
            if not event_id:
                raise DatasetConfigurationError(
                    f"Normal-window row {row_number} has no source_event_id"
                )
            if event_id in windows:
                raise DatasetConfigurationError(
                    f"Duplicate normal-window source_event_id: {event_id}"
                )
            for field in ("review_version", "reviewer", "reviewed_at", "rationale"):
                if not normalized[field]:
                    raise DatasetConfigurationError(
                        f"Normal-window row {row_number} has no {field}"
                    )
            try:
                start = int(normalized["normal_start_frame"])
                end = int(normalized["normal_end_frame"])
            except ValueError as error:
                raise DatasetConfigurationError(
                    f"Normal-window row {row_number} has malformed frame bounds"
                ) from error
            if start < 0 or end < start:
                raise DatasetConfigurationError(
                    f"Normal-window row {row_number} has invalid frame bounds"
                )
            windows[event_id] = normalized
        return windows


def load_category_policy(path: Path) -> dict[str, Any]:
    policy = load_json(path)
    if not isinstance(policy, dict) or not isinstance(policy.get("categories"), list):
        raise DatasetConfigurationError("DoTA category policy is malformed")
    seen: set[tuple[int, str]] = set()
    allowed_actions = {
        "INCLUDE_ACCIDENT",
        "POSSIBLE_NON_ACCIDENT_SOURCE",
        "EXCLUDE_AMBIGUOUS",
        "EXCLUDE_OUT_OF_SCOPE",
        "REVIEW_REQUIRED",
    }
    for category in policy["categories"]:
        try:
            key = (int(category["annotation_id"]), str(category["viewpoint"]))
            action = category["iris_action"]
            annotation_name = category["annotation_name"]
        except (KeyError, TypeError, ValueError) as error:
            raise DatasetConfigurationError("Malformed DoTA category entry") from error
        if key in seen:
            raise DatasetConfigurationError(f"Duplicate DoTA category mapping: {key}")
        if action not in allowed_actions or not annotation_name:
            raise DatasetConfigurationError(f"Invalid DoTA category mapping: {key}")
        seen.add(key)
    return policy


def load_extraction_policy(path: Path) -> dict[str, Any]:
    policy = load_json(path)
    required_integer_fields = (
        "source_frames_per_second",
        "normal_pre_event_buffer_frames",
        "minimum_temporal_spacing_frames",
        "maximum_accident_frames_per_event",
        "maximum_normal_frames_per_event",
    )
    if not isinstance(policy, dict):
        raise DatasetConfigurationError("Extraction policy root must be an object")
    if not policy.get("extraction_version"):
        raise DatasetConfigurationError("Extraction policy has no version")
    for field in required_integer_fields:
        value = policy.get(field)
        if not isinstance(value, int) or value < 0:
            raise DatasetConfigurationError(
                f"Extraction policy {field} must be a non-negative integer"
            )
    if policy["source_frames_per_second"] == 0:
        raise DatasetConfigurationError("source_frames_per_second must be positive")
    if policy.get("copy_mode") != "BYTE_PRESERVING":
        raise DatasetConfigurationError("Only BYTE_PRESERVING extraction is supported")
    if policy.get("normal_reviewed_window_required") is not True:
        raise DatasetConfigurationError(
            "TASK 006 requires a reviewed normal window for non-accident frames"
        )
    if policy.get("accident_visible_window_required") is not True:
        raise DatasetConfigurationError(
            "TASK 006 requires a reviewed visible-collision window"
        )
    if policy.get("post_event_normal_enabled") is not False:
        raise DatasetConfigurationError(
            "Post-event frames are not approved as normal examples"
        )
    extensions = policy.get("allowed_source_extensions")
    if not isinstance(extensions, list) or not extensions:
        raise DatasetConfigurationError("allowed_source_extensions must be a list")
    if any(
        not isinstance(extension, str)
        or not extension.startswith(".")
        or extension != extension.lower()
        for extension in extensions
    ):
        raise DatasetConfigurationError(
            "allowed_source_extensions must contain lowercase dot-prefixed values"
        )
    return policy


def select_spaced_frames(
    frame_indices: list[int], maximum_count: int, minimum_spacing: int
) -> list[int]:
    if maximum_count <= 0 or not frame_indices:
        return []
    spaced: list[int] = []
    for frame in sorted(set(frame_indices)):
        if not spaced or frame - spaced[-1] >= minimum_spacing:
            spaced.append(frame)
    if len(spaced) <= maximum_count:
        return spaced
    if maximum_count == 1:
        return [spaced[len(spaced) // 2]]
    selected_positions = [
        round(index * (len(spaced) - 1) / (maximum_count - 1))
        for index in range(maximum_count)
    ]
    return [spaced[position] for position in selected_positions]


def _category_action(
    annotation: dict[str, Any], category_policy: dict[str, Any]
) -> str:
    viewpoint = "ego" if annotation.get("ego_involve") is True else "other"
    annotation_id = int(annotation.get("accident_id"))
    annotation_name = annotation.get("accident_name")
    for category in category_policy["categories"]:
        if (
            int(category["annotation_id"]) == annotation_id
            and category["viewpoint"] == viewpoint
            and category["annotation_name"] == annotation_name
        ):
            return category["iris_action"]
    raise DatasetConfigurationError(
        f"No category policy for {annotation_id}/{annotation_name}/{viewpoint}"
    )


def _copy_and_describe(source: Path, destination: Path) -> tuple[str, int, int, str]:
    source_hash = sha256_file(source)
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        if sha256_file(destination) != source_hash:
            raise DatasetConfigurationError(
                f"Refusing to overwrite different derived bytes: {destination}"
            )
    else:
        shutil.copyfile(source, destination)
    probe = probe_image(destination)
    return source_hash, probe.width, probe.height, probe.perceptual_hash


def extract_dota_frames(
    annotation_root: Path,
    source_root: Path,
    output_root: Path,
    normal_windows: dict[str, dict[str, str]],
    visible_windows: dict[str, dict[str, str]],
    category_policy: dict[str, Any],
    extraction_policy: dict[str, Any],
    source_registry_entry: dict[str, Any],
) -> ExtractionResult:
    if source_registry_entry.get("usage_status") != "APPROVED":
        raise DatasetConfigurationError(
            "DoTA source usage is not APPROVED; extraction is blocked"
        )
    if source_registry_entry.get("derived_data_status") != "APPROVED":
        raise DatasetConfigurationError(
            "DoTA derived-data permission is not APPROVED; extraction is blocked"
        )
    if category_policy.get("policy_status") != "APPROVED":
        raise DatasetConfigurationError(
            "DoTA category policy is not APPROVED; extraction is blocked"
        )
    if extraction_policy.get("policy_status") != "APPROVED":
        raise DatasetConfigurationError(
            "DoTA extraction policy is not APPROVED; extraction is blocked"
        )

    annotations = sorted(annotation_root.glob("*.json"))
    if not annotations:
        raise DatasetConfigurationError(
            f"No DoTA annotation JSON files found in {annotation_root}"
        )
    rows: list[dict[str, str]] = []
    warnings: list[str] = []
    fps = extraction_policy["source_frames_per_second"]
    buffer_frames = extraction_policy["normal_pre_event_buffer_frames"]
    spacing = extraction_policy["minimum_temporal_spacing_frames"]
    maximum_normal = extraction_policy["maximum_normal_frames_per_event"]
    maximum_accident = extraction_policy["maximum_accident_frames_per_event"]

    for annotation_path in annotations:
        try:
            annotation = json.loads(annotation_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            raise DatasetConfigurationError(
                f"Malformed DoTA annotation: {annotation_path}"
            ) from error
        event_id = annotation.get("video_name")
        if not isinstance(event_id, str) or not event_id:
            raise DatasetConfigurationError(
                f"DoTA annotation has no video_name: {annotation_path}"
            )
        video_id = source_video_id(event_id)
        ignored = annotation.get("ignore")
        if not isinstance(ignored, bool):
            raise DatasetConfigurationError(
                f"DoTA annotation has no Boolean ignore flag: {event_id}"
            )
        if ignored:
            warnings.append(f"{event_id}: official annotation is ignored; clip skipped")
            continue
        labels = annotation.get("labels")
        if not isinstance(labels, list):
            raise DatasetConfigurationError(f"DoTA annotation has no labels: {event_id}")
        frames_by_id = {
            int(label["frame_id"]): label
            for label in labels
            if isinstance(label, dict) and "frame_id" in label
        }
        anomaly_start = int(annotation["anomaly_start"])
        anomaly_end = int(annotation["anomaly_end"])
        normal_end = anomaly_start - buffer_frames - 1
        selected: list[tuple[str, int, str]] = []
        normal_window = normal_windows.get(event_id)
        if normal_window is None:
            warnings.append(
                f"{event_id}: no reviewed normal window; non-accident frames skipped"
            )
        else:
            reviewed_normal_start = int(normal_window["normal_start_frame"])
            reviewed_normal_end = int(normal_window["normal_end_frame"])
            if reviewed_normal_end > normal_end:
                raise DatasetConfigurationError(
                    f"Reviewed normal window for {event_id} must end before the "
                    "configured pre-event exclusion buffer"
                )
            normal_candidates = [
                frame_id
                for frame_id in frames_by_id
                if reviewed_normal_start <= frame_id <= reviewed_normal_end
            ]
            selected.extend(
                (
                    "non_accident",
                    frame_id,
                    "human_reviewed_normal_window_before_configured_buffer",
                )
                for frame_id in select_spaced_frames(
                    normal_candidates, maximum_normal, spacing
                )
            )

        action = _category_action(annotation, category_policy)
        window = visible_windows.get(event_id)
        if action == "INCLUDE_ACCIDENT" and window is None:
            warnings.append(
                f"{event_id}: no reviewed visible-collision window; accident frames skipped"
            )
        elif action == "INCLUDE_ACCIDENT" and window is not None:
            visible_start = int(window["visible_start_frame"])
            visible_end = int(window["visible_end_frame"])
            if visible_start < anomaly_start or visible_end > anomaly_end:
                raise DatasetConfigurationError(
                    f"Reviewed visible window for {event_id} must be inside the "
                    "official anomaly window"
                )
            accident_candidates = [
                frame_id
                for frame_id in frames_by_id
                if visible_start <= frame_id <= visible_end
            ]
            selected.extend(
                (
                    "accident",
                    frame_id,
                    "human_reviewed_visible_collision_window",
                )
                for frame_id in select_spaced_frames(
                    accident_candidates, maximum_accident, spacing
                )
            )

        for label, frame_id, label_basis in selected:
            frame = frames_by_id[frame_id]
            source_relative = Path(str(frame.get("image_path", "")))
            source_path = (source_root / source_relative).resolve()
            if not source_path.is_relative_to(source_root.resolve()):
                raise DatasetConfigurationError(
                    f"Unsafe source image path in {event_id}: {source_relative}"
                )
            if not source_path.is_file():
                raise DatasetConfigurationError(
                    f"Source frame is missing: {source_relative}"
                )
            extension = source_path.suffix.lower()
            if extension not in extraction_policy["allowed_source_extensions"]:
                raise DatasetConfigurationError(
                    f"Unsupported source frame extension: {source_path}"
                )
            output_relative = Path("dota") / event_id / label / source_path.name
            destination = output_root / output_relative
            digest, width, height, perceptual_hash = _copy_and_describe(
                source_path, destination
            )
            viewpoint = "ego" if annotation.get("ego_involve") is True else "other"
            rows.append(
                {
                    "manifest_version": MANIFEST_VERSION,
                    "item_id": f"dota-{event_id}-{frame_id:06d}-{label}",
                    "relative_path": output_relative.as_posix(),
                    "label": label,
                    "split": "",
                    "source_dataset_id": source_registry_entry["dataset_id"],
                    "source_dataset_version": source_registry_entry["dataset_version"],
                    "source_group_id": f"dota-official:{video_id}",
                    "source_event_id": event_id,
                    "source_video_id": video_id,
                    "source_frame_index": str(frame_id),
                    "source_timestamp_ms": str(round(frame_id * 1000 / fps)),
                    "source_reference": OFFICIAL_REPOSITORY,
                    "source_category": category_name(annotation),
                    "label_basis": label_basis,
                    "license_status": "APPROVED",
                    "sha256": digest,
                    "perceptual_hash": perceptual_hash,
                    "extraction_version": extraction_policy["extraction_version"],
                    "width": str(width),
                    "height": str(height),
                    "day_night": "night" if annotation.get("night") else "day",
                    "weather": "",
                    "ego_involvement": viewpoint,
                    "accident_category": str(annotation.get("accident_name", "")),
                }
            )

    return ExtractionResult(
        rows=tuple(sorted(rows, key=lambda row: row["item_id"])),
        warnings=tuple(warnings),
    )
