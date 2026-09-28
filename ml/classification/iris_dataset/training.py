"""Reproducible, rights-gated binary classifier training primitives.

This module deliberately keeps model training optional: the repository does
not install a training framework, and production training is refused until a
validated manifest contains approved samples from both classes.
"""

from __future__ import annotations

import hashlib
import io
import json
import random
import re
import zipfile
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
    if initialization not in {"random", "approved_checkpoint", "official_imagenet"}:
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
        from torchvision.models import MobileNet_V3_Small_Weights, mobilenet_v3_small
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
    elif initialization == "official_imagenet":
        weights = MobileNet_V3_Small_Weights.IMAGENET1K_V1
    else:
        raise TrainingBlockedError(f"Unsupported initialization: {initialization}")
    model = mobilenet_v3_small(weights=weights)
    model.classifier[3] = nn.Linear(model.classifier[3].in_features, 1)
    if checkpoint is not None and initialization == "approved_checkpoint":
        import torch

        model.load_state_dict(torch.load(checkpoint, map_location="cpu"))
    return model


def train_authorized_experimental_v0(
    freeze_rows: list[dict[str, str]],
    split_rows: list[dict[str, str]],
    output_dir: Path,
    *,
    seed: int = 6006,
    epochs: int = 8,
    batch_size: int = 32,
    learning_rate: float = 0.001,
    weight_decay: float = 0.0001,
) -> dict[str, Any]:
    """Run the authorized archive-backed V0 experiment using real torchvision weights.

    This function intentionally accepts the frozen split rather than the
    production manifest. It must only be called after the experimental
    authorization preflight has passed.
    """
    try:
        import torch
        from torch.utils.data import DataLoader, Dataset
        from torchvision.models import MobileNet_V3_Small_Weights
    except ImportError as error:
        raise TrainingBlockedError("PyTorch and torchvision are required") from error
    if output_dir.exists():
        raise TrainingBlockedError(f"Experimental output directory already exists: {output_dir}")
    freeze_by_item = {row["item_id"]: row for row in freeze_rows}
    if len(freeze_by_item) != 1000 or len(split_rows) != 1000:
        raise TrainingBlockedError("Authorized V0 training requires exactly 1000 frozen rows")
    rows: list[dict[str, str]] = []
    for split_row in split_rows:
        frozen = freeze_by_item.get(split_row["item_id"])
        if frozen is None or frozen["sha256"] != split_row["sha256"]:
            raise TrainingBlockedError("Split does not match the authorized freeze")
        rows.append({**frozen, "split": split_row["split"]})
    if {row["split"] for row in rows} != {"train", "validation", "test"}:
        raise TrainingBlockedError("Authorized V0 split is incomplete")
    random.seed(seed)
    torch.manual_seed(seed)
    torch.set_num_threads(1)
    torch.use_deterministic_algorithms(True, warn_only=True)
    if torch.backends.cudnn.is_available():
        torch.backends.cudnn.deterministic = True
        torch.backends.cudnn.benchmark = False
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    weights = MobileNet_V3_Small_Weights.IMAGENET1K_V1
    model = build_mobilenet_v3_small(initialization="official_imagenet")
    for parameter in model.features.parameters():
        parameter.requires_grad = False
    model.to(device)

    class ArchiveDataset(Dataset):
        def __init__(self, dataset_rows: list[dict[str, str]]) -> None:
            self.rows = dataset_rows
            self.archives: dict[str, zipfile.ZipFile] = {}

        def __len__(self) -> int:
            return len(self.rows)

        def __getitem__(self, index: int):
            row = self.rows[index]
            archive_path, member = row["source_reference"].split("::", 1)
            archive = self.archives.get(archive_path)
            if archive is None:
                archive = zipfile.ZipFile(archive_path)
                self.archives[archive_path] = archive
            data = archive.read(member)
            if hashlib.sha256(data).hexdigest() != row["sha256"]:
                raise TrainingBlockedError(f"Archive source hash mismatch: {row['item_id']}")
            with Image.open(io.BytesIO(data)) as source:
                image = source.convert("RGB")
            contained = ImageOps.contain(image, (224, 224), method=Image.Resampling.BILINEAR)
            canvas = Image.new("RGB", (224, 224), (0, 0, 0))
            canvas.paste(contained, ((224 - contained.width) // 2, (224 - contained.height) // 2))
            pixels = torch.frombuffer(bytearray(canvas.tobytes()), dtype=torch.uint8)
            pixels = pixels.reshape(224, 224, 3).permute(2, 0, 1).float().div_(255.0)
            mean = torch.tensor((0.485, 0.456, 0.406)).reshape(3, 1, 1)
            std = torch.tensor((0.229, 0.224, 0.225)).reshape(3, 1, 1)
            label = 1.0 if row["label"] == "accident" else 0.0
            return (pixels - mean) / std, torch.tensor([label]), row["item_id"]

    train_rows = [row for row in rows if row["split"] == "train"]
    validation_rows = [row for row in rows if row["split"] == "validation"]
    test_rows = [row for row in rows if row["split"] == "test"]
    if (len(train_rows), len(validation_rows), len(test_rows)) != (700, 150, 150):
        raise TrainingBlockedError("Authorized V0 split counts are invalid")
    generator = torch.Generator().manual_seed(seed)
    train_loader = DataLoader(ArchiveDataset(train_rows), batch_size=batch_size, shuffle=True, generator=generator)
    validation_loader = DataLoader(ArchiveDataset(validation_rows), batch_size=batch_size, shuffle=False)
    test_loader = DataLoader(ArchiveDataset(test_rows), batch_size=batch_size, shuffle=False)
    optimizer = torch.optim.AdamW(
        (parameter for parameter in model.parameters() if parameter.requires_grad),
        lr=learning_rate,
        weight_decay=weight_decay,
    )
    loss_function = torch.nn.BCEWithLogitsLoss()

    def infer(loader: Any) -> tuple[list[int], list[float], list[str], float]:
        model.eval()
        labels: list[int] = []
        scores: list[float] = []
        item_ids: list[str] = []
        total_loss = 0.0
        with torch.no_grad():
            for images, batch_labels, batch_ids in loader:
                images, batch_labels = images.to(device), batch_labels.to(device)
                logits = model(images)
                total_loss += float(loss_function(logits, batch_labels).detach().cpu())
                scores.extend(torch.sigmoid(logits).reshape(-1).cpu().tolist())
                labels.extend(int(value) for value in batch_labels.reshape(-1).cpu().tolist())
                item_ids.extend(batch_ids)
        return labels, scores, item_ids, total_loss / max(1, len(loader))

    output_dir.mkdir(parents=True)
    print("IRIS experimental run: training started", flush=True)
    history: list[dict[str, float]] = []
    best_epoch = 0
    best_validation_loss = float("inf")
    checkpoint_path = output_dir / "best_model.pt"
    for epoch in range(1, epochs + 1):
        model.train()
        total_train_loss = 0.0
        for images, labels, _ids in train_loader:
            images, labels = images.to(device), labels.to(device)
            optimizer.zero_grad(set_to_none=True)
            loss = loss_function(model(images), labels)
            loss.backward()
            optimizer.step()
            total_train_loss += float(loss.detach().cpu())
        validation_labels, validation_scores, _validation_ids, validation_loss = infer(validation_loader)
        history.append({"epoch": epoch, "train_loss": total_train_loss / len(train_loader), "validation_loss": validation_loss})
        print(
            f"IRIS experimental run: epoch={epoch} train_loss={history[-1]['train_loss']:.6f} validation_loss={validation_loss:.6f}",
            flush=True,
        )
        if validation_loss < best_validation_loss:
            best_validation_loss = validation_loss
            best_epoch = epoch
            torch.save(model.state_dict(), checkpoint_path)
    model.load_state_dict(torch.load(checkpoint_path, map_location=device, weights_only=True))
    validation_labels, validation_scores, _validation_ids, validation_loss = infer(validation_loader)
    threshold = select_validation_threshold(validation_labels, validation_scores)
    validation_predictions = [1 if score >= threshold["threshold"] else 0 for score in validation_scores]
    validation_metrics = binary_metrics(validation_labels, validation_predictions)
    decisions = {
        "architecture": "MobileNetV3Small",
        "weights_identifier": "MobileNet_V3_Small_Weights.IMAGENET1K_V1",
        "weights_source": weights.url,
        "weights_meta": weights.meta,
        "preprocess": {"decode": "RGB", "resize": "aspect-preserving contain", "size": [224, 224], "padding": "centered black", "normalization": "ImageNet mean/std"},
        "class_mapping": {"non_accident": 0, "accident": 1},
        "best_epoch": best_epoch,
        "best_checkpoint_selection": "minimum validation loss",
        "best_validation_loss": best_validation_loss,
        "threshold": threshold,
        "test_locked_before_evaluation": True,
    }
    (output_dir / "decisions_locked.json").write_text(json.dumps(decisions, indent=2) + "\n", encoding="utf-8")
    print("IRIS experimental run: decisions locked; evaluating held-out test", flush=True)
    test_labels, test_scores, test_ids, test_loss = infer(test_loader)
    test_predictions = [1 if score >= threshold["threshold"] else 0 for score in test_scores]
    test_metrics = binary_metrics(test_labels, test_predictions)
    test_metrics["accuracy"] = sum(prediction == label for prediction, label in zip(test_predictions, test_labels)) / len(test_labels)
    errors: list[dict[str, Any]] = []
    for item_id, label, score, prediction in zip(test_ids, test_labels, test_scores, test_predictions):
        if label == prediction:
            continue
        row = freeze_by_item[item_id]
        errors.append({"item_id": item_id, "source_dataset_id": row["source_dataset_id"], "source_reference": row["source_reference"], "true_label": row["label"], "model_score": score, "predicted_label": "accident" if prediction else "non_accident", "threshold": threshold["threshold"]})
    with (output_dir / "held_out_test_errors.csv").open("w", encoding="utf-8", newline="") as handle:
        import csv
        fields = ("item_id", "source_dataset_id", "source_reference", "true_label", "model_score", "predicted_label", "threshold")
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(errors)
    checkpoint_hash = sha256_file(checkpoint_path)
    metadata = {
        "status": "COMPLETE_EXPERIMENTAL_ONLY",
        "device": str(device),
        "cuda_available": torch.cuda.is_available(),
        "torch_version": torch.__version__,
        "torchvision_version": __import__("torchvision").__version__,
        "seed": seed,
        "optimizer": "AdamW classifier head only",
        "learning_rate": learning_rate,
        "weight_decay": weight_decay,
        "batch_size": batch_size,
        "maximum_epochs": epochs,
        "epochs_completed": len(history),
        "augmentation": "none",
        "history": history,
        "validation": {"loss": validation_loss, "metrics": validation_metrics, "threshold": threshold},
        "held_out_test": {"loss": test_loss, "metrics": test_metrics, "misclassifications": len(errors)},
        "checkpoint": {"path": checkpoint_path.as_posix(), "sha256": checkpoint_hash},
        "decisions_locked_before_test": decisions,
    }
    write_run_metadata(output_dir, metadata)
    print("IRIS experimental run: held-out evaluation complete", flush=True)
    return metadata


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
