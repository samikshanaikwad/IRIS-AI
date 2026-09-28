"""Validate the accepted V0 TFLite artifact against PyTorch on real frozen images."""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import math
import sys
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[3]
CLASSIFICATION_ROOT = ROOT / "ml/classification"
if str(CLASSIFICATION_ROOT) not in sys.path:
    sys.path.insert(0, str(CLASSIFICATION_ROOT))

EXPECTED_CHECKPOINT_SHA256 = (
    "10ace06ef6fb97ea8559e29340f4f326ab2fc0c33f40691fbb4157124b4f9c3b"
)
THRESHOLD = 0.8611480594
FLOAT32_TOLERANCE = 1e-4
MEAN = np.asarray([0.485, 0.456, 0.406], dtype=np.float32)
STD = np.asarray([0.229, 0.224, 0.225], dtype=np.float32)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_freeze(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def load_image(data: bytes) -> np.ndarray:
    with Image.open(io.BytesIO(data)) as source:
        image = source.convert("RGB")
    contained = ImageOps.contain(image, (224, 224), method=Image.Resampling.BILINEAR)
    canvas = Image.new("RGB", (224, 224), (0, 0, 0))
    offset = ((224 - contained.width) // 2, (224 - contained.height) // 2)
    canvas.paste(contained, offset)
    array = np.asarray(canvas, dtype=np.float32) / 255.0
    array = (array - MEAN) / STD
    return np.transpose(array, (2, 0, 1)).astype(np.float32)


def read_source(row: dict[str, str]) -> bytes:
    archive_text, member = row["source_reference"].split("::", 1)
    with zipfile.ZipFile(ROOT / archive_text) as archive:
        data = archive.read(member)
    if hashlib.sha256(data).hexdigest() != row["sha256"]:
        raise RuntimeError(f"source hash mismatch: {row['item_id']}")
    return data


def sigmoid(value: float) -> float:
    return 1.0 / (1.0 + math.exp(-value))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--tflite", type=Path, required=True)
    parser.add_argument("--freeze", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--contract", type=Path, required=True)
    args = parser.parse_args()
    checkpoint_sha = sha256_file(args.checkpoint)
    if checkpoint_sha != EXPECTED_CHECKPOINT_SHA256:
        raise SystemExit(f"ERROR: checkpoint SHA mismatch: {checkpoint_sha}")
    contract = json.loads(args.contract.read_text(encoding="utf-8"))
    if contract.get("source_checkpoint_sha256") != checkpoint_sha:
        raise SystemExit("ERROR: model contract source checkpoint hash mismatch")
    tflite_sha = sha256_file(args.tflite)
    if contract.get("tflite_sha256") != tflite_sha:
        raise SystemExit("ERROR: model contract TFLite hash mismatch")
    if float(contract["output"]["threshold"]) != THRESHOLD:
        raise SystemExit("ERROR: model contract threshold mismatch")
    rows = sorted(load_freeze(args.freeze), key=lambda row: row["item_id"])
    if len(rows) != 1000:
        raise SystemExit(f"ERROR: expected 1000 freeze rows, found {len(rows)}")

    import tensorflow as tf
    import torch

    from iris_dataset.training import build_mobilenet_v3_small

    model = build_mobilenet_v3_small("approved_checkpoint", args.checkpoint)
    model.eval()
    selected: list[dict[str, str]] = []
    for label in ("accident", "non_accident"):
        label_rows = [row for row in rows if row["label"] == label]
        # Fixed rank-spaced selection keeps the parity set deterministic and
        # covers the source ordering without using test labels for tuning.
        indexes = sorted({int(round(i * (len(label_rows) - 1) / 14)) for i in range(15)})
        selected.extend(label_rows[index] for index in indexes)
    tensors: dict[str, np.ndarray] = {
        row["item_id"]: load_image(read_source(row)) for row in selected
    }
    with torch.no_grad():
        batch = torch.from_numpy(np.stack([tensors[row["item_id"]] for row in selected]))
        logits = model(batch).reshape(-1).numpy()
    scores = {row["item_id"]: sigmoid(float(logit)) for row, logit in zip(selected, logits)}

    if len(selected) < 30:
        raise SystemExit(f"ERROR: deterministic parity set has only {len(selected)} rows")

    interpreter = tf.lite.Interpreter(model_path=str(args.tflite))
    interpreter.allocate_tensors()
    input_detail = interpreter.get_input_details()[0]
    output_detail = interpreter.get_output_details()[0]
    input_shape = tuple(int(value) for value in input_detail["shape"])
    input_dtype = str(np.dtype(input_detail["dtype"]))
    output_shape = tuple(int(value) for value in output_detail["shape"])
    output_dtype = str(np.dtype(output_detail["dtype"]))
    if input_dtype != "float32" or output_dtype != "float32":
        raise SystemExit("ERROR: conversion is not float32")

    records: list[dict[str, object]] = []
    disagreements = 0
    differences: list[float] = []
    for row in selected:
        tensor = tensors[row["item_id"]][None, ...]
        if input_shape == (1, 224, 224, 3):
            tensor = np.transpose(tensor, (0, 2, 3, 1))
            layout = "NHWC"
        elif input_shape == (1, 3, 224, 224):
            layout = "NCHW"
        else:
            raise SystemExit(f"ERROR: unsupported TFLite input shape: {input_shape}")
        interpreter.set_tensor(input_detail["index"], tensor.astype(np.float32))
        interpreter.invoke()
        raw = float(np.asarray(interpreter.get_tensor(output_detail["index"])).reshape(-1)[0])
        tflite_score = sigmoid(raw)
        pytorch_score = scores[row["item_id"]]
        difference = abs(pytorch_score - tflite_score)
        differences.append(difference)
        pytorch_prediction = "accident" if pytorch_score >= THRESHOLD else "non_accident"
        tflite_prediction = "accident" if tflite_score >= THRESHOLD else "non_accident"
        disagreements += pytorch_prediction != tflite_prediction
        records.append(
            {
                "item_id": row["item_id"],
                "label": row["label"],
                "source_dataset_id": row["source_dataset_id"],
                "source_reference": row["source_reference"],
                "pytorch_model_score": pytorch_score,
                "tflite_raw_output": raw,
                "tflite_model_score": tflite_score,
                "pytorch_threshold_label": pytorch_prediction,
                "tflite_threshold_label": tflite_prediction,
                "threshold": THRESHOLD,
            }
        )

    args.output_dir.mkdir(parents=True, exist_ok=True)
    csv_path = args.output_dir / "tflite_parity.csv"
    with csv_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=records[0].keys(), lineterminator="\n")
        writer.writeheader()
        writer.writerows(records)
    result = {
        "status": "PASS" if disagreements == 0 and max(differences) <= FLOAT32_TOLERANCE else "FAIL",
        "checkpoint_sha256": checkpoint_sha,
        "tflite_sha256": tflite_sha,
        "parity_samples": len(records),
        "class_counts": {
            label: sum(row["label"] == label for row in selected)
            for label in ("accident", "non_accident")
        },
        "input_shape": list(input_shape),
        "input_dtype": input_dtype,
        "input_layout": layout,
        "output_shape": list(output_shape),
        "output_dtype": output_dtype,
        "sigmoid": "outside_graph",
        "threshold": THRESHOLD,
        "float32_tolerance": FLOAT32_TOLERANCE,
        "max_absolute_score_difference": max(differences),
        "mean_absolute_score_difference": sum(differences) / len(differences),
        "threshold_classification_disagreements": disagreements,
    }
    (args.output_dir / "tflite_parity.json").write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
