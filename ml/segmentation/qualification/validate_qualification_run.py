"""Fail-closed validation for a real segmentation qualification run.

This script does not generate masks. A model-specific runner must execute a
governed artifact and record real outputs first. The validator prevents a test
fixture, unhashed model, unlicensed image, or non-device result from being
reported as an IRIS Android qualification.
"""

import argparse
import hashlib
import json
from pathlib import Path


INVENTORY_SCHEMA = "iris-segmentation-candidate-inventory-v1"
RUN_SCHEMA = "iris-segmentation-qualification-run-v1"
REQUIRED_CLASSES = {"bicycle", "car", "motorcycle", "bus", "truck"}
TASK007_DETECTOR_SHA256 = (
    "2e04c53bfeac0ac2a30c057c7e2a777594ce39baaac35a92f74fb1e8c4fc4e0b"
)
MAX_QUALIFICATION_TOTAL_MS = 35_000
MAX_QUALIFICATION_PEAK_PSS_BYTES = 1_610_612_736  # 1.5 GiB


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"JSON object required: {path}")
    return value


def validate_inventory(path: Path) -> dict:
    inventory = load_json(path)
    if inventory.get("schema_version") != INVENTORY_SCHEMA:
        raise ValueError("unexpected candidate-inventory schema")
    if set(inventory.get("required_vehicle_classes", [])) != REQUIRED_CLASSES:
        raise ValueError("required vehicle class contract changed")
    candidates = inventory.get("candidates")
    if not isinstance(candidates, list) or not candidates:
        raise ValueError("candidate inventory is empty")
    ids = set()
    for candidate in candidates:
        if not isinstance(candidate, dict):
            raise ValueError("candidate entry must be an object")
        candidate_id = candidate.get("id")
        if not isinstance(candidate_id, str) or not candidate_id or candidate_id in ids:
            raise ValueError("candidate IDs must be unique nonempty strings")
        ids.add(candidate_id)
        if candidate.get("decision") not in {"BLOCKED", "REJECTED", "QUALIFIED"}:
            raise ValueError(f"invalid candidate decision: {candidate_id}")
        for field in ("official_source", "license", "class_contract", "offline_android_path"):
            if not isinstance(candidate.get(field), str) or not candidate[field].strip():
                raise ValueError(f"missing {field}: {candidate_id}")
    return inventory


def require_hashed_file(entry: dict, base: Path, label: str) -> Path:
    relative = entry.get("path")
    expected = entry.get("sha256")
    if not isinstance(relative, str) or not isinstance(expected, str) or len(expected) != 64:
        raise ValueError(f"{label} requires a relative path and SHA-256")
    path = (base / relative).resolve()
    if base.resolve() not in path.parents:
        raise ValueError(f"{label} path escapes the qualification directory")
    if not path.is_file():
        raise ValueError(f"{label} file is missing: {relative}")
    if sha256(path) != expected.lower():
        raise ValueError(f"{label} SHA-256 mismatch: {relative}")
    return path


def validate_run(inventory: dict, run_path: Path) -> None:
    run = load_json(run_path)
    if run.get("schema_version") != RUN_SCHEMA:
        raise ValueError("unexpected qualification-run schema")
    candidates = {entry["id"]: entry for entry in inventory["candidates"]}
    candidate_id = run.get("candidate_id")
    if candidate_id not in candidates:
        raise ValueError("run references an unknown candidate")
    if candidates[candidate_id]["decision"] != "QUALIFIED":
        raise ValueError("only a qualified candidate can produce a qualifying run")
    if run.get("coordinate_contract_version") != "iris-image-coordinate-v2":
        raise ValueError("run did not use the current image-coordinate contract")
    device = run.get("device")
    if not isinstance(device, dict) or not all(
        isinstance(device.get(field), str) and device[field].strip()
        for field in ("manufacturer", "model", "android_version", "abi")
    ):
        raise ValueError("physical Android device identity is incomplete")
    if device.get("emulator") is not False:
        raise ValueError("physical-device qualification is required")

    base = run_path.parent
    artifacts = run.get("model_artifacts")
    if not isinstance(artifacts, list) or not artifacts:
        raise ValueError("no governed model artifacts recorded")
    for index, artifact in enumerate(artifacts):
        require_hashed_file(artifact, base, f"model artifact {index}")

    images = run.get("evaluation_images")
    if not isinstance(images, list) or not images:
        raise ValueError("no genuine evaluation images recorded")
    image_ids = set()
    for image in images:
        if image.get("synthetic") is not False:
            raise ValueError("synthetic images cannot establish model quality")
        if image.get("rights_status") != "CLEARED":
            raise ValueError("evaluation image rights are not cleared")
        if not image.get("source") or not image.get("license_or_permission"):
            raise ValueError("evaluation image provenance is incomplete")
        require_hashed_file(image, base, "evaluation image")
        image_ids.add(image.get("id"))

    results = run.get("results")
    if not isinstance(results, list) or not results:
        raise ValueError("no real inference results recorded")
    observed_success = set()
    successful_image_ids = set()
    for result in results:
        if result.get("image_id") not in image_ids:
            raise ValueError("result references an unknown evaluation image")
        status = result.get("status")
        if status not in {"SUCCESS", "UNSUPPORTED_CLASS", "NO_RELIABLE_MASK", "ERROR"}:
            raise ValueError("invalid result status")
        vehicle_class = result.get("vehicle_class")
        if vehicle_class not in REQUIRED_CLASSES:
            raise ValueError("result class is outside the IRIS qualification contract")
        if status == "SUCCESS":
            if result.get("prompt_source") != "TASK007_REAL_DETECTION":
                raise ValueError("successful mask requires genuine TASK007 prompt provenance")
            if result.get("detector_sha256") != TASK007_DETECTOR_SHA256:
                raise ValueError("successful mask used an unexpected detector artifact")
            if not isinstance(result.get("prompt_count"), int) or result["prompt_count"] <= 0:
                raise ValueError("successful mask requires at least one real detector prompt")
            masks = result.get("masks")
            if not isinstance(masks, list) or len(masks) != result["prompt_count"]:
                raise ValueError("every real detector prompt requires one recorded mask")
            for index, mask in enumerate(masks):
                require_hashed_file(mask, base, f"mask {index}")
            require_hashed_file(result["overlay"], base, "overlay")
            review = result.get("visual_review")
            if (
                not isinstance(review, dict)
                or review.get("decision") != "ACCEPTED"
                or not isinstance(review.get("notes"), str)
                or not review["notes"].strip()
            ):
                raise ValueError("successful mask requires an accepted documented visual review")
            observed_success.add(vehicle_class)
            successful_image_ids.add(result["image_id"])
        elif status == "NO_RELIABLE_MASK":
            if result.get("masks") or result.get("overlay"):
                raise ValueError("failed evaluation must not carry mask artifacts")
            if not isinstance(result.get("failure_reason"), str) or not result["failure_reason"].strip():
                raise ValueError("failed evaluation requires an explicit reason")
    if set(run.get("claimed_supported_classes", [])) != observed_success:
        raise ValueError("claimed classes do not equal successful real results")

    metrics = run.get("device_metrics")
    if not isinstance(metrics, dict):
        raise ValueError("device metrics are missing")
    if metrics.get("memory_metric") != "sampled_process_pss":
        raise ValueError("qualification requires the sampled process PSS metric actually measured on Android")
    peak_pss = metrics.get("peak_pss_bytes")
    if not isinstance(peak_pss, int) or peak_pss <= 0:
        raise ValueError("positive measured peak process PSS is required")
    if peak_pss > MAX_QUALIFICATION_PEAK_PSS_BYTES:
        raise ValueError("measured peak process PSS exceeds the qualification threshold")
    per_image = metrics.get("per_image")
    if not isinstance(per_image, list) or not per_image:
        raise ValueError("per-image device measurements are required")
    measured_image_ids = set()
    for sample in per_image:
        if not isinstance(sample, dict) or sample.get("image_id") not in successful_image_ids:
            raise ValueError("device metric references a non-successful image")
        measured_image_ids.add(sample["image_id"])
        for field in ("detector_ms", "encoder_ms", "decoder_ms", "total_ms"):
            value = sample.get(field)
            if not isinstance(value, (int, float)) or value <= 0:
                raise ValueError(f"positive measured {field} is required")
        if sample["total_ms"] > MAX_QUALIFICATION_TOTAL_MS:
            raise ValueError("measured total latency exceeds the qualification threshold")
        sample_pss = sample.get("sampled_peak_pss_bytes")
        if not isinstance(sample_pss, int) or sample_pss <= 0:
            raise ValueError("positive per-image sampled process PSS is required")
    if measured_image_ids != successful_image_ids:
        raise ValueError("every successful image requires device latency and memory measurements")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--inventory", type=Path, required=True)
    parser.add_argument("--run", type=Path)
    args = parser.parse_args()
    inventory = validate_inventory(args.inventory)
    if args.run is None:
        print("Segmentation candidate inventory validation: PASS (not a model qualification)")
        return
    validate_run(inventory, args.run)
    print("Segmentation qualification evidence validation: PASS")


if __name__ == "__main__":
    main()
