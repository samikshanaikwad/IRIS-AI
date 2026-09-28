"""Reproducible, rights-gated binary classifier training primitives.

This module deliberately keeps model training optional: the repository does
not install a training framework, and production training is refused until a
validated manifest contains approved samples from both classes.
"""

from __future__ import annotations

import hashlib
import json
import random
import re
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, Sequence

from PIL import Image, ImageOps

from .image_tools import sha256_file
from .manifest import DatasetConfigurationError, load_json, load_manifest, load_source_registry
from .splitting import assign_group_splits, load_split_policy

LABELS = ("accident", "non_accident")
SPLITS = ("train", "validation", "test")
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
DHASH_PATTERN = re.compile(r"^[0-9a-f]{16}$")


class TrainingBlockedError(RuntimeError):
    """Raised when training cannot safely begin."""


@dataclass(frozen=True)
class PreprocessConfig:
    input_width: int = 224
    input_height: int = 224
    pad_value: tuple[int, int, int] = (0, 0, 0)
    normalization_mean: tuple[float, float, float] = (0.485, 0.456, 0.406)
    normalization_std: tuple[float, float, float] = (0.229, 0.224, 0.225)

    def as_json(self) -> dict[str, Any]:
        return {
            "input_width": self.input_width,
            "input_height": self.input_height,
            "resize": "aspect-preserving contain with centered padding",
            "pad_value": list(self.pad_value),
            "normalization": {
                "mean": list(self.normalization_mean),
                "std": list(self.normalization_std),
            },
        }


@dataclass(frozen=True)
class TrainingConfig:
    seed: int
    epochs: int
    batch_size: int
    learning_rate: float
    weight_decay: float
    initialization: str
    pretrained_checkpoint: str | None
    preprocess: PreprocessConfig


def load_training_config(path: Path) -> TrainingConfig:
    payload = load_json(path)
    if not isinstance(payload, dict):
        raise DatasetConfigurationError("Training config root must be an object")
    preprocess_payload = payload.get("preprocess", {})
    normalization = preprocess_payload.get("normalization", {})
    preprocess = PreprocessConfig(
        input_width=int(preprocess_payload.get("input_width", 224)),
        input_height=int(preprocess_payload.get("input_height", 224)),
        pad_value=tuple(preprocess_payload.get("pad_value", [0, 0, 0])),
        normalization_mean=tuple(normalization.get("mean", [0.485, 0.456, 0.406])),
        normalization_std=tuple(normalization.get("std", [0.229, 0.224, 0.225])),
    )
    if preprocess.input_width <= 0 or preprocess.input_height <= 0:
        raise DatasetConfigurationError("Preprocess dimensions must be positive")
    initialization = payload.get("initialization")
    if initialization not in {"random", "approved_checkpoint"}:
        raise DatasetConfigurationError(
            "initialization must be 'random' or 'approved_checkpoint'"
        )
    checkpoint = payload.get("pretrained_checkpoint")
    if initialization == "approved_checkpoint" and not checkpoint:
        raise DatasetConfigurationError(
            "approved_checkpoint initialization requires pretrained_checkpoint"
        )
    return TrainingConfig(
        seed=int(payload.get("seed", 6006)),
        epochs=int(payload.get("epochs", 20)),
        batch_size=int(payload.get("batch_size", 32)),
        learning_rate=float(payload.get("learning_rate", 0.001)),
        weight_decay=float(payload.get("weight_decay", 0.0001)),
        initialization=initialization,
        pretrained_checkpoint=checkpoint,
        preprocess=preprocess,
    )


def _safe_path(data_root: Path, relative_path: str) -> Path:
    relative = Path(relative_path)
    if relative.is_absolute():
        raise TrainingBlockedError(f"Absolute image path is not allowed: {relative_path}")
    root = data_root.resolve()
    candidate = (root / relative).resolve()
    if not candidate.is_relative_to(root):
        raise TrainingBlockedError(f"Image path escapes data root: {relative_path}")
    return candidate


def _dhash_distance(first: str, second: str) -> int:
    return (int(first, 16) ^ int(second, 16)).bit_count()


def validate_training_rows(
    rows: list[dict[str, str]],
    data_root: Path,
    *,
    near_duplicate_threshold: int = 4,
    require_all_classes_in_each_split: bool = True,
) -> list[str]:
    """Return hard preflight errors without modifying the manifest."""

    errors: list[str] = []
    labels = {row.get("label", "") for row in rows}
    for label in LABELS:
        if label not in labels:
            errors.append(f"APPROVED_{label.upper()}_SAMPLES_MISSING")

    group_splits: dict[str, set[str]] = defaultdict(set)
    sha_splits: dict[str, set[str]] = defaultdict(set)
    dhashes: list[tuple[str, str, str]] = []
    split_labels: dict[str, set[str]] = defaultdict(set)
    seen_items: set[str] = set()

    for row in rows:
        item_id = row.get("item_id", "")
        if not item_id:
            errors.append("MISSING_ITEM_ID")
        elif item_id in seen_items:
            errors.append(f"DUPLICATE_ITEM_ID:{item_id}")
        seen_items.add(item_id)
        label = row.get("label", "")
        split = row.get("split", "")
        group = row.get("source_group_id", "")
        if label not in LABELS:
            errors.append(f"INVALID_LABEL:{item_id}")
        if split not in SPLITS:
            errors.append(f"INVALID_INTERNAL_SPLIT:{item_id}")
        if not group:
            errors.append(f"MISSING_SOURCE_GROUP_ID:{item_id}")
        if not row.get("source_event_id"):
            errors.append(f"MISSING_SOURCE_EVENT_ID:{item_id}")
        if not row.get("label_basis"):
            errors.append(f"MISSING_LABEL_BASIS:{item_id}")
        if row.get("license_status") != "APPROVED":
            errors.append(f"ITEM_RIGHTS_NOT_APPROVED:{item_id}")
        if not row.get("sha256") or not SHA256_PATTERN.fullmatch(row["sha256"]):
            errors.append(f"INVALID_SHA256:{item_id}")
        if not row.get("perceptual_hash") or not DHASH_PATTERN.fullmatch(row["perceptual_hash"]):
            errors.append(f"INVALID_PERCEPTUAL_HASH:{item_id}")
        try:
            image_path = _safe_path(data_root, row.get("relative_path", ""))
        except TrainingBlockedError as error:
            errors.append(f"UNSAFE_PATH:{item_id}:{error}")
            continue
        if not image_path.is_file():
            errors.append(f"MISSING_FILE:{item_id}")
        elif sha256_file(image_path) != row.get("sha256"):
            errors.append(f"HASH_MISMATCH:{item_id}")
        if split in SPLITS:
            split_labels[split].add(label)
            group_splits[group].add(split)
            sha_splits[row.get("sha256", "")].add(split)
            dhashes.append((item_id, split, row.get("perceptual_hash", "")))

    errors.extend(
        f"SOURCE_GROUP_CROSSES_SPLITS:{group}:{sorted(splits)}"
        for group, splits in sorted(group_splits.items())
        if len(splits) > 1
    )
    errors.extend(
        f"CROSS_SPLIT_EXACT_DUPLICATE:{sha}"
        for sha, splits in sorted(sha_splits.items())
        if sha and len(splits) > 1
    )
    if require_all_classes_in_each_split:
        for split in SPLITS:
            missing = set(LABELS) - split_labels.get(split, set())
            errors.extend(f"MISSING_{label.upper()}_IN_{split.upper()}" for label in sorted(missing))
    for index, (item_id, split, digest) in enumerate(dhashes):
        if not digest:
            continue
        for other_id, other_split, other_digest in dhashes[index + 1 :]:
            if split != other_split and _dhash_distance(digest, other_digest) <= near_duplicate_threshold:
                errors.append(f"CROSS_SPLIT_NEAR_DUPLICATE:{item_id}:{other_id}")
    return sorted(set(errors))


def prepare_group_split(
    rows: list[dict[str, str]], policy_path: Path
) -> list[dict[str, str]]:
    """Assign deterministic group splits and reject insufficient group coverage."""

    policy = load_split_policy(policy_path)
    assigned = assign_group_splits(rows, policy)
    groups_by_label: dict[str, set[str]] = defaultdict(set)
    for row in assigned:
        groups_by_label[row["label"]].add(row[policy["group_field"]])
    if any(len(groups_by_label[label]) < 3 for label in LABELS):
        raise TrainingBlockedError(
            "At least three independent groups per class are required for train/validation/test"
        )
    group_splits: dict[str, set[str]] = defaultdict(set)
    for row in assigned:
        group_splits[row[policy["group_field"]]].add(row["split"])
    leaking_groups = [group for group, splits in group_splits.items() if len(splits) != 1]
    if leaking_groups:
        raise TrainingBlockedError(
            "Invalid group split: " + ", ".join(sorted(leaking_groups))
        )
    return assigned


def preflight_manifest(
    manifest_path: Path,
    data_root: Path,
    registry_path: Path | None = None,
) -> dict[str, Any]:
    """Return a machine-readable training gate decision."""

    rows = load_manifest(manifest_path)
    errors = validate_training_rows(rows, data_root)
    if registry_path is not None:
        registry = load_source_registry(registry_path)
        for row in rows:
            source = registry.get(row.get("source_dataset_id"))
            if source is None:
                errors.append(f"MISSING_SOURCE_REGISTRY:{row.get('item_id', '')}")
            elif source.get("usage_status") != "APPROVED" or source.get("derived_data_status") != "APPROVED":
                errors.append(f"SOURCE_RIGHTS_NOT_APPROVED:{row.get('item_id', '')}")
    counts = {label: sum(row.get("label") == label for row in rows) for label in LABELS}
    blocked_reason = None
    if counts["accident"] == 0:
        blocked_reason = "No approved accident-positive training samples are present."
    elif counts["non_accident"] == 0:
        blocked_reason = "No approved non-accident training samples are present."
    elif errors:
        blocked_reason = "Manifest integrity or rights validation failed."
    return {
        "status": "READY" if blocked_reason is None else "BLOCKED",
        "training_allowed": blocked_reason is None,
        "rows": len(rows),
        "class_counts": counts,
        "errors": sorted(set(errors)),
        "blocked_reason": blocked_reason,
        "message": (
            "Production classifier training has not occurred because no "
            "rights-cleared accident-positive training samples are currently approved."
            if counts["accident"] == 0
            else blocked_reason
        ),
    }


def preprocess_image(path: Path, config: PreprocessConfig) -> Image.Image:
    """Decode an image and produce deterministic aspect-preserving RGB input."""

    with Image.open(path) as source:
        image = source.convert("RGB")
    contained = ImageOps.contain(image, (config.input_width, config.input_height), method=Image.Resampling.BILINEAR)
    canvas = Image.new("RGB", (config.input_width, config.input_height), config.pad_value)
    offset = ((config.input_width - contained.width) // 2, (config.input_height - contained.height) // 2)
    canvas.paste(contained, offset)
    return canvas


def select_validation_threshold(labels: Sequence[int], scores: Sequence[float]) -> dict[str, Any]:
    """Select a deterministic threshold from validation data only."""

    if len(labels) != len(scores) or not labels:
        raise TrainingBlockedError("Validation labels and model scores must be non-empty and equal length")
    if set(labels) != {0, 1}:
        raise TrainingBlockedError("Validation threshold selection requires both classes")
    candidates = sorted({0.0, 1.0, *[max(0.0, min(1.0, float(score))) for score in scores]})
    best: tuple[float, float, float] | None = None
    for threshold in candidates:
        predicted = [1 if score >= threshold else 0 for score in scores]
        metrics = binary_metrics(labels, predicted)
        key = (metrics["balanced_accuracy"], -abs(threshold - 0.5), -threshold)
        if best is None or key > best:
            best = key
            selected = {"threshold": threshold, "balanced_accuracy": metrics["balanced_accuracy"]}
    return {
        **selected,
        "source_split": "validation",
        "method": "maximum validation balanced accuracy; deterministic ties prefer threshold nearest 0.5",
        "score_name": "model score",
    }


def binary_metrics(labels: Sequence[int], predictions: Sequence[int]) -> dict[str, Any]:
    if len(labels) != len(predictions) or not labels:
        raise ValueError("Labels and predictions must be non-empty and equal length")
    tp = sum(label == 1 and prediction == 1 for label, prediction in zip(labels, predictions))
    tn = sum(label == 0 and prediction == 0 for label, prediction in zip(labels, predictions))
    fp = sum(label == 0 and prediction == 1 for label, prediction in zip(labels, predictions))
    fn = sum(label == 1 and prediction == 0 for label, prediction in zip(labels, predictions))
    recall = tp / (tp + fn) if tp + fn else None
    specificity = tn / (tn + fp) if tn + fp else None
    precision = tp / (tp + fp) if tp + fp else None
    f1 = 2 * precision * recall / (precision + recall) if precision is not None and recall is not None and precision + recall else None
    balanced = (recall + specificity) / 2 if recall is not None and specificity is not None else None
    return {
        "true_positive": tp,
        "true_negative": tn,
        "false_positive": fp,
        "false_negative": fn,
        "sensitivity_recall": recall,
        "specificity": specificity,
        "precision": precision,
        "f1": f1,
        "balanced_accuracy": balanced,
    }


def build_mobilenet_v3_small(initialization: str = "random", checkpoint: Path | None = None):
    """Build the optional real MobileNetV3Small path without downloading weights."""

    try:
        import torch.nn as nn
        from torchvision.models import mobilenet_v3_small
    except ImportError as error:
        raise TrainingBlockedError(
            "PyTorch and torchvision are optional and must be installed for actual training"
        ) from error
    if initialization == "approved_checkpoint":
        if checkpoint is None or not checkpoint.is_file():
            raise TrainingBlockedError("Approved local checkpoint is missing")
        weights = None
    elif initialization == "random":
        weights = None
    else:
        raise TrainingBlockedError(f"Unsupported initialization: {initialization}")
    model = mobilenet_v3_small(weights=weights)
    model.classifier[3] = nn.Linear(model.classifier[3].in_features, 1)
    if checkpoint is not None and initialization == "approved_checkpoint":
        import torch

        model.load_state_dict(torch.load(checkpoint, map_location="cpu"))
    return model


def train_mobilenet_v3_small(
    rows: list[dict[str, str]],
    data_root: Path,
    config: TrainingConfig,
    output_dir: Path,
    manifest_digest: str | None = None,
) -> dict[str, Any]:
    """Train and evaluate a real model after the admission gate passes.

    PyTorch/torchvision remain optional dependencies. This function never
    downloads weights and writes artifacts only after preflight succeeds.
    """

    errors = validate_training_rows(rows, data_root)
    if errors:
        raise TrainingBlockedError("Training preflight failed: " + "; ".join(errors))
    try:
        import torch
        from torch.utils.data import DataLoader, Dataset
    except ImportError as error:
        raise TrainingBlockedError(
            "PyTorch is required for actual training and is not installed"
        ) from error

    random.seed(config.seed)
    torch.manual_seed(config.seed)
    if torch.backends.cudnn.is_available():
        torch.backends.cudnn.deterministic = True
        torch.backends.cudnn.benchmark = False
    model = build_mobilenet_v3_small(
        initialization=config.initialization,
        checkpoint=Path(config.pretrained_checkpoint)
        if config.pretrained_checkpoint
        else None,
    )

    class ManifestDataset(Dataset):
        def __init__(self, dataset_rows: list[dict[str, str]]):
            self.rows = dataset_rows

        def __len__(self) -> int:
            return len(self.rows)

        def __getitem__(self, index: int):
            row = self.rows[index]
            image = preprocess_image(_safe_path(data_root, row["relative_path"]), config.preprocess)
            pixels = torch.tensor(list(image.getdata()), dtype=torch.float32)
            pixels = pixels.reshape(config.preprocess.input_height, config.preprocess.input_width, 3)
            pixels = pixels.permute(2, 0, 1) / 255.0
            mean = torch.tensor(config.preprocess.normalization_mean).reshape(3, 1, 1)
            std = torch.tensor(config.preprocess.normalization_std).reshape(3, 1, 1)
            return (pixels - mean) / std, torch.tensor([1.0 if row["label"] == "accident" else 0.0])

    train_rows = [row for row in rows if row["split"] == "train"]
    validation_rows = [row for row in rows if row["split"] == "validation"]
    test_rows = [row for row in rows if row["split"] == "test"]
    loader = DataLoader(ManifestDataset(train_rows), batch_size=config.batch_size, shuffle=True)
    optimizer = torch.optim.AdamW(model.parameters(), lr=config.learning_rate, weight_decay=config.weight_decay)
    loss_function = torch.nn.BCEWithLogitsLoss()
    history: list[dict[str, float]] = []
    model.train()
    for epoch in range(config.epochs):
        total_loss = 0.0
        for images, labels in loader:
            optimizer.zero_grad()
            loss = loss_function(model(images), labels)
            loss.backward()
            optimizer.step()
            total_loss += float(loss.detach())
        history.append({"epoch": epoch + 1, "train_loss": total_loss / max(1, len(loader))})

    def scores(dataset_rows: list[dict[str, str]]) -> tuple[list[int], list[float]]:
        model.eval()
        labels: list[int] = []
        outputs: list[float] = []
        with torch.no_grad():
            for images, batch_labels in DataLoader(ManifestDataset(dataset_rows), batch_size=config.batch_size):
                outputs.extend(torch.sigmoid(model(images)).reshape(-1).tolist())
                labels.extend(int(value) for value in batch_labels.reshape(-1).tolist())
        return labels, outputs

    validation_labels, validation_scores = scores(validation_rows)
    threshold = select_validation_threshold(validation_labels, validation_scores)
    test_labels, test_scores = scores(test_rows)
    test_predictions = [1 if score >= threshold["threshold"] else 0 for score in test_scores]
    evaluation = binary_metrics(test_labels, test_predictions)
    output_dir.mkdir(parents=True, exist_ok=True)
    model_path = output_dir / "model.pt"
    torch.save(model.state_dict(), model_path)
    metadata = {
        "model_format": "PyTorch state_dict",
        "architecture": "MobileNetV3Small",
        "manifest_sha256": manifest_digest,
        "preprocess": config.preprocess.as_json(),
        "threshold": threshold,
        "history": history,
        "held_out_test": evaluation,
        "model_sha256": sha256_file(model_path),
    }
    write_run_metadata(output_dir, metadata)
    return metadata


def write_run_metadata(output_dir: Path, payload: dict[str, Any]) -> Path:
    """Write metadata only for a real completed/prepared run."""

    output_dir.mkdir(parents=True, exist_ok=True)
    path = output_dir / "run_metadata.json"
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return path


def manifest_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()
