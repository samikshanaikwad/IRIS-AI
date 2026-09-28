from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CLASSIFICATION_ROOT = ROOT / "ml/classification"
if str(CLASSIFICATION_ROOT) not in sys.path:
    sys.path.insert(0, str(CLASSIFICATION_ROOT))

from iris_dataset.experimental import load_freeze, validate_experimental_preflight
from iris_dataset.training import train_authorized_experimental_v0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--freeze", type=Path, required=True)
    parser.add_argument("--authorization", type=Path, required=True)
    parser.add_argument("--split", type=Path, required=True)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    if args.output_dir.exists():
        raise SystemExit(f"ERROR: output directory already exists: {args.output_dir}")
    preflight = validate_experimental_preflight(
        args.freeze, args.authorization, args.split, ROOT
    )
    if preflight["status"] != "PASS":
        raise SystemExit("ERROR: experimental V0 preflight did not pass")
    with args.config.open("r", encoding="utf-8") as handle:
        config = json.load(handle)
    with args.split.open("r", encoding="utf-8-sig", newline="") as handle:
        import csv
        split_rows = list(csv.DictReader(handle))
    metadata = train_authorized_experimental_v0(
        load_freeze(args.freeze),
        split_rows,
        args.output_dir,
        seed=int(config["seed"]),
        epochs=int(config["maximum_epochs"]),
        batch_size=int(config["batch_size"]),
        learning_rate=float(config["learning_rate"]),
        weight_decay=float(config["weight_decay"]),
    )
    print(json.dumps({"preflight": preflight, "run": metadata}, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
