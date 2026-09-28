"""Validate the frozen TASK 007A EfficientDet-Lite0 contract and artifact."""
import argparse
import hashlib
import json
import zipfile
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def validate(contract_path: Path, artifact_path: Path) -> None:
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    detector = contract["detector"]
    if not artifact_path.is_file():
        raise ValueError(f"detector artifact missing: {artifact_path}")
    actual_sha = sha256(artifact_path)
    if actual_sha != detector["artifact_sha256"]:
        raise ValueError(f"artifact SHA-256 mismatch: {actual_sha}")
    if artifact_path.stat().st_size != detector["artifact_size_bytes"]:
        raise ValueError("artifact size mismatch")
    required = contract["label_map"]["required_road_classes"]
    with zipfile.ZipFile(artifact_path) as archive:
        label_bytes = archive.read(contract["label_map"]["embedded_filename"])
    if hashlib.sha256(label_bytes).hexdigest() != contract["label_map"]["sha256"]:
        raise ValueError("embedded label map SHA-256 mismatch")
    labels = label_bytes.decode("utf-8").splitlines()
    actual = {name: labels.index(name) for name in required}
    if actual != required:
        raise ValueError(f"label IDs mismatch: {actual}")
    if contract["output"]["nms"] != "Included in the model graph/postprocessing; IRIS must not apply a second NMS stage.":
        raise ValueError("unexpected NMS contract")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--artifact", type=Path, required=True)
    args = parser.parse_args()
    validate(args.contract, args.artifact)
    print("V0 detector contract validation: PASS")


if __name__ == "__main__":
    main()
