"""Validate the qualified TASK 009A.2 ORT depth contract and artifact."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate(contract_path: Path, artifact_path: Path) -> None:
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    model = contract["model"]
    artifact = contract["mobile_artifact"]
    if model["checkpoint_sha256"].lower() != "715fade13be8f229f8a70cc02066f656f2423a59effd0579197bbf57860e1378":
        raise ValueError("unexpected source checkpoint SHA-256")
    if artifact["format"] != "ONNX Runtime ORT format":
        raise ValueError("unexpected mobile format")
    if not artifact_path.is_file():
        raise FileNotFoundError(artifact_path)
    if sha256(artifact_path) != artifact["sha256"]:
        raise ValueError("mobile artifact SHA-256 mismatch")
    if artifact_path.stat().st_size != artifact["size_bytes"]:
        raise ValueError("mobile artifact size mismatch")
    if contract["input"] != {
        "shape": [1, 3, 518, 518],
        "dtype": "float32",
        "layout": "NCHW",
        "color_order": "RGB",
        "preprocessing": contract["input"]["preprocessing"],
    }:
        raise ValueError("unexpected input contract")
    if contract["output"]["shape"] != [1, 518, 518] or contract["output"]["dtype"] != "float32":
        raise ValueError("unexpected output contract")
    if contract["model"]["semantics"] != "relative depth; not meters; larger values represent nearer/foreground structure":
        raise ValueError("unexpected depth semantics")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--artifact", type=Path, required=True)
    args = parser.parse_args()
    validate(args.contract, args.artifact)
    print("V0 ORT depth contract validation: PASS")


if __name__ == "__main__":
    main()
