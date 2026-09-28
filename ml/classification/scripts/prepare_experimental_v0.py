from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CLASSIFICATION_ROOT = ROOT / "ml/classification"
if str(CLASSIFICATION_ROOT) not in sys.path:
    sys.path.insert(0, str(CLASSIFICATION_ROOT))

from iris_dataset.experimental import (  # noqa: E402
    load_freeze,
    prepare_splits,
    selected_digest,
    sha256_file,
    validate_experimental_preflight,
    verify_archived_sources,
    write_authorization,
    write_split_manifest,
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--freeze", type=Path, required=True)
    parser.add_argument("--authorization", type=Path, required=True)
    parser.add_argument("--split-manifest", type=Path, required=True)
    args = parser.parse_args()
    rows = load_freeze(args.freeze)
    integrity = verify_archived_sources(rows, ROOT)
    split_rows, split_metadata = prepare_splits(rows, seed=6006)
    write_split_manifest(args.split_manifest, split_rows)
    freeze_digest = sha256_file(args.freeze)
    write_authorization(
        args.authorization,
        args.freeze,
        freeze_digest,
        rows,
        {**split_metadata, "integrity": integrity},
    )
    preflight = validate_experimental_preflight(
        args.freeze, args.authorization, args.split_manifest, ROOT
    )
    print(
        json.dumps(
            {
                "status": "PASS",
                "freeze_manifest_sha256": freeze_digest,
                "selected_sample_digest": selected_digest(rows),
                "integrity": integrity,
                "split": split_metadata,
                "preflight": preflight,
                "authorization": args.authorization.as_posix(),
                "split_manifest": args.split_manifest.as_posix(),
            },
            indent=2,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
