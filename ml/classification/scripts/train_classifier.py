from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

CLASSIFICATION_ROOT = Path(__file__).resolve().parents[1]
if str(CLASSIFICATION_ROOT) not in sys.path:
    sys.path.insert(0, str(CLASSIFICATION_ROOT))

from iris_dataset.manifest import load_manifest
from iris_dataset.training import (
    TrainingBlockedError,
    load_training_config,
    preflight_manifest,
    manifest_sha256,
    train_mobilenet_v3_small,
)

ROOT = Path(__file__).resolve().parents[3]
MANIFEST = ROOT / "datasets/manifests/classification/manifest.v1.csv"
REGISTRY = ROOT / "datasets/manifests/classification/source_registry.v1.json"
DATA_ROOT = ROOT / "datasets/derived/classification"


def main() -> int:
    parser = argparse.ArgumentParser(description="IRIS real classifier training gate")
    parser.add_argument("command", choices=("preflight", "train"))
    parser.add_argument("--manifest", type=Path, default=MANIFEST)
    parser.add_argument("--registry", type=Path, default=REGISTRY)
    parser.add_argument("--data-root", type=Path, default=DATA_ROOT)
    parser.add_argument(
        "--config",
        type=Path,
        default=ROOT / "ml/classification/configs/classifier_training.v1.json",
    )
    parser.add_argument("--output-dir", type=Path, default=ROOT / "ml/runs/classification")
    args = parser.parse_args()
    result = preflight_manifest(args.manifest, args.data_root, args.registry)
    print(json.dumps(result, indent=2, sort_keys=True))
    if not result["training_allowed"]:
        return 2
    if args.command == "train":
        try:
            metadata = train_mobilenet_v3_small(
                load_manifest(args.manifest),
                args.data_root,
                load_training_config(args.config),
                args.output_dir,
                manifest_digest=manifest_sha256(args.manifest),
            )
        except TrainingBlockedError as error:
            print(json.dumps({"status": "BLOCKED", "error": str(error)}, indent=2))
            return 2
        print(json.dumps({"status": "COMPLETE", "metadata": metadata}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
