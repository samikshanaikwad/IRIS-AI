"""Fetch the governed public Phase A2 images using normal TLS validation.

Images are kept under ignored local tooling, never written into a case, and
accepted only when their downloaded bytes match the reviewed SHA-256 manifest.
"""

import argparse
import hashlib
import json
import urllib.request
from pathlib import Path


SCHEMA = "iris-public-vehicle-segmentation-evaluation-v1"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    if manifest.get("schema_version") != SCHEMA:
        raise ValueError("unexpected public-evaluation manifest schema")
    args.output.mkdir(parents=True, exist_ok=True)
    for entry in manifest.get("images", []):
        if entry.get("synthetic") is not False or entry.get("rights_status") != "CLEARED":
            raise ValueError(f"image is not eligible: {entry.get('id')}")
        target = args.output / entry["asset_name"]
        if not args.verify_only and not target.is_file():
            request = urllib.request.Request(
                entry["download_url"],
                headers={"User-Agent": "IRIS-development-qualification/1.0"},
            )
            with urllib.request.urlopen(request) as response, target.open("wb") as output:
                while block := response.read(1024 * 1024):
                    output.write(block)
        if not target.is_file() or sha256(target) != entry["sha256"]:
            raise ValueError(f"SHA-256 mismatch or missing image: {entry['asset_name']}")
        print(f"VERIFIED {entry['id']} {entry['sha256']}")


if __name__ == "__main__":
    main()
