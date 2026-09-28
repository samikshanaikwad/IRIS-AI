from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-dir", type=Path, required=True)
    args = parser.parse_args()
    metadata = json.loads((args.run_dir / "run_metadata.json").read_text(encoding="utf-8"))
    decisions = json.loads((args.run_dir / "decisions_locked.json").read_text(encoding="utf-8"))
    checkpoint = args.run_dir / "best_model.pt"
    if sha256_file(checkpoint) != metadata["checkpoint"]["sha256"]:
        raise SystemExit("ERROR: checkpoint SHA-256 mismatch")
    threshold = metadata["validation"]["threshold"]
    if threshold != decisions["threshold"] or threshold["source_split"] != "validation":
        raise SystemExit("ERROR: threshold metadata is not validation-locked")
    if not decisions.get("test_locked_before_evaluation"):
        raise SystemExit("ERROR: test lock was not recorded before evaluation")
    metrics = metadata["held_out_test"]["metrics"]
    total = sum(
        metrics[name]
        for name in ("true_positive", "true_negative", "false_positive", "false_negative")
    )
    if total != 150:
        raise SystemExit(f"ERROR: held-out confusion matrix total is {total}, not 150")
    with (args.run_dir / "held_out_test_errors.csv").open("r", encoding="utf-8-sig", newline="") as handle:
        errors = list(csv.DictReader(handle))
    if len(errors) != metadata["held_out_test"]["misclassifications"]:
        raise SystemExit("ERROR: error analysis does not match held-out misclassification count")
    print(json.dumps({"status": "PASS", "checkpoint_sha256": metadata["checkpoint"]["sha256"], "held_out_total": total, "misclassifications": len(errors)}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
