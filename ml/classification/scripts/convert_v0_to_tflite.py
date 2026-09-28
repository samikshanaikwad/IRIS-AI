"""Convert the accepted IRIS V0 PyTorch checkpoint to float32 TFLite.

This script intentionally converts only the immutable accepted checkpoint. It
does not train, tune, quantize, or change preprocessing. The generated ONNX
file is a scratch intermediate and the generated TFLite file is written to
the ignored model-run directory.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CLASSIFICATION_ROOT = ROOT / "ml/classification"
if str(CLASSIFICATION_ROOT) not in sys.path:
    sys.path.insert(0, str(CLASSIFICATION_ROOT))

EXPECTED_CHECKPOINT_SHA256 = (
    "10ace06ef6fb97ea8559e29340f4f326ab2fc0c33f40691fbb4157124b4f9c3b"
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    checkpoint = args.checkpoint.resolve()
    output_dir = args.output_dir.resolve()
    if not checkpoint.is_file():
        raise SystemExit(f"ERROR: checkpoint is missing: {checkpoint}")
    checkpoint_sha = sha256_file(checkpoint)
    if checkpoint_sha != EXPECTED_CHECKPOINT_SHA256:
        raise SystemExit(
            "ERROR: accepted checkpoint SHA-256 mismatch: " + checkpoint_sha
        )
    output_dir.mkdir(parents=True, exist_ok=True)
    onnx_path = output_dir / "mobilenet_v3_small_v0_logits.onnx"
    tflite_dir = output_dir / "tflite-conversion"
    tflite_dir.mkdir(exist_ok=True)

    import torch

    from iris_dataset.training import build_mobilenet_v3_small

    model = build_mobilenet_v3_small("approved_checkpoint", checkpoint)
    model.eval()
    example = torch.zeros((1, 3, 224, 224), dtype=torch.float32)
    with torch.no_grad():
        torch.onnx.export(
            model,
            example,
            onnx_path,
            input_names=["input"],
            output_names=["logit"],
            opset_version=18,
            do_constant_folding=True,
            dynamo=False,
        )

    command = [
        sys.executable,
        "-m",
        "onnx2tf",
        "-i",
        str(onnx_path),
        "-o",
        str(tflite_dir),
        "-osd",
        "--non_verbose",
    ]
    subprocess.run(command, check=True, cwd=ROOT)
    candidates = sorted(tflite_dir.glob("*float32*.tflite"))
    if len(candidates) != 1:
        raise SystemExit(
            f"ERROR: expected one float32 TFLite artifact, found {len(candidates)}"
        )
    final_path = output_dir / "mobilenet_v3_small_v0_float32.tflite"
    final_path.write_bytes(candidates[0].read_bytes())
    metadata = {
        "checkpoint_sha256": checkpoint_sha,
        "checkpoint": checkpoint.as_posix(),
        "onnx_path": onnx_path.as_posix(),
        "tflite_path": final_path.as_posix(),
        "tflite_sha256": sha256_file(final_path),
        "conversion_route": "PyTorch -> ONNX -> onnx2tf -> float32 TFLite",
        "input_shape": [1, 3, 224, 224],
        "input_dtype": "float32",
        "output_name": "logit",
        "output_shape": [1, 1],
        "sigmoid": "outside_graph",
        "quantization": "none; float32",
    }
    (output_dir / "conversion_metadata.json").write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(json.dumps(metadata, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
