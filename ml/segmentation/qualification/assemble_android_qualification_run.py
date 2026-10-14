"""Assemble a fail-closed qualification package from captured Android results.

The script does not run inference or create masks. It verifies and copies the
already captured public-image sources, MobileSAM artifacts, masks, overlays,
and device measurements into one ignored local package for validation.
"""

import argparse
import hashlib
import json
import shutil
from pathlib import Path


PUBLIC_SCHEMA = "iris-public-vehicle-segmentation-evaluation-v1"
REVIEW_SCHEMA = "iris-public-segmentation-visual-review-v1"
RUN_SCHEMA = "iris-segmentation-qualification-run-v1"
RESULT_SCHEMA = "iris-public-segmentation-device-result-v1"
DETECTOR_SHA256 = "2e04c53bfeac0ac2a30c057c7e2a777594ce39baaac35a92f74fb1e8c4fc4e0b"
ENCODER_SHA256 = "f55b0f6c6949d4737ba06ddf14b99b35ae7c26c782f9865078e34b0a0f45df49"
DECODER_SHA256 = "4a3d6ee977ce5ad077e1ab980db5f1bffb96758c4029a2abccd0d08634a8bf63"


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


def copy_hashed(source: Path, destination: Path, expected: str | None = None) -> dict:
    if not source.is_file():
        raise ValueError(f"captured artifact is missing: {source}")
    actual = sha256(source)
    if expected is not None and actual != expected.lower():
        raise ValueError(f"captured artifact SHA-256 mismatch: {source.name}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    return {"path": destination.as_posix(), "sha256": actual}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--reviews", type=Path, required=True)
    parser.add_argument("--device-results", type=Path, required=True)
    parser.add_argument("--models", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    manifest = load_json(args.manifest)
    reviews = load_json(args.reviews)
    if manifest.get("schema_version") != PUBLIC_SCHEMA:
        raise ValueError("unexpected public-evaluation manifest schema")
    if reviews.get("schema_version") != REVIEW_SCHEMA:
        raise ValueError("unexpected visual-review schema")
    review_by_id = {entry["image_id"]: entry for entry in reviews.get("reviews", [])}

    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    model_entries = []
    for name, expected in (
        ("mobilesam_vit_t_encoder.onnx", ENCODER_SHA256),
        ("mobilesam_vit_t_box_decoder.onnx", DECODER_SHA256),
    ):
        relative = Path("models") / name
        model_entries.append(
            copy_hashed(args.models / name, output / relative, expected) | {"path": relative.as_posix()}
        )
    license_relative = Path("models") / "MOBILE_SAM_LICENSE.txt"
    model_entries.append(
        copy_hashed(
            args.models / license_relative.name,
            output / license_relative,
        ) | {"path": license_relative.as_posix(), "role": "upstream_license"}
    )

    evaluation_images = []
    results = []
    per_image_metrics = []
    successful_classes = set()
    peak_pss_bytes = 0

    for image in manifest.get("images", []):
        image_id = image["id"]
        source = args.device_results / f"source-{image['asset_name']}"
        relative_image = Path("images") / image["asset_name"]
        image_entry = copy_hashed(source, output / relative_image, image["sha256"])
        evaluation_images.append({
            "id": image_id,
            "path": relative_image.as_posix(),
            "sha256": image_entry["sha256"],
            "synthetic": False,
            "rights_status": image["rights_status"],
            "source": image["source_page"],
            "license_or_permission": image["license"],
        })

        captured = load_json(args.device_results / f"{image_id}-result.json")
        if captured.get("schema_version") != RESULT_SCHEMA:
            raise ValueError(f"unexpected captured-result schema: {image_id}")
        if captured.get("evaluation_image", {}).get("sha256") != image["sha256"]:
            raise ValueError(f"captured image provenance changed: {image_id}")
        if captured.get("detector_sha256") != DETECTOR_SHA256:
            raise ValueError(f"unexpected TASK007 detector: {image_id}")
        review = review_by_id.get(image_id)
        if not isinstance(review, dict):
            raise ValueError(f"visual review is missing: {image_id}")

        if captured.get("status") == "NO_ELIGIBLE_DETECTOR_BOX":
            if review.get("decision") != "REJECTED":
                raise ValueError(f"detector failure must remain rejected: {image_id}")
            results.append({
                "image_id": image_id,
                "status": "NO_RELIABLE_MASK",
                "vehicle_class": image["supported_vehicle_class"],
                "detector_sha256": DETECTOR_SHA256,
                "prompt_count": 0,
                "failure_reason": review.get("notes"),
                "observed_detector_classes": sorted({
                    item["class_name"] for item in captured.get("detector_detections", [])
                }),
            })
            continue

        if captured.get("status") != "MASKS_GENERATED_ON_DEVICE":
            raise ValueError(f"captured run is not a usable result: {image_id}")
        if review.get("decision") != "ACCEPTED":
            raise ValueError(f"successful device masks lack accepted visual review: {image_id}")
        segmentation = captured.get("segmentation", {})
        if (
            segmentation.get("coordinateContractVersion") != "iris-image-coordinate-v2"
            or segmentation.get("encoderSha256") != ENCODER_SHA256
            or segmentation.get("decoderSha256") != DECODER_SHA256
        ):
            raise ValueError(f"captured model/coordinate provenance changed: {image_id}")
        prompt_results = segmentation.get("promptMaskResults", [])
        if len(prompt_results) != captured.get("target_detection_count") or not prompt_results:
            raise ValueError(f"captured prompt/mask count mismatch: {image_id}")
        masks = []
        quality = []
        for index, prompt in enumerate(prompt_results):
            if prompt.get("status") != "MASK_READY":
                raise ValueError(f"captured prompt produced no mask: {image_id}/{index}")
            source_mask = args.device_results / Path(prompt["maskPath"]).name
            relative_mask = Path("masks") / source_mask.name
            masks.append(
                copy_hashed(source_mask, output / relative_mask, prompt["maskFileSha256"])
                | {"path": relative_mask.as_posix()}
            )
            quality.append({
                "predicted_quality": prompt["predictedQuality"],
                "mask_box_iou": prompt["maskBoundingBoxIou"],
                "mask_to_box_area_ratio": prompt["maskToBoxAreaRatio"],
                "mask_raster_sha256": prompt["maskRasterSha256"],
            })
        source_overlay = args.device_results / Path(segmentation["overlayPath"]).name
        relative_overlay = Path("overlays") / source_overlay.name
        overlay = copy_hashed(
            source_overlay,
            output / relative_overlay,
            segmentation["overlaySha256"],
        ) | {"path": relative_overlay.as_posix()}
        vehicle_class = image["supported_vehicle_class"]
        results.append({
            "image_id": image_id,
            "status": "SUCCESS",
            "vehicle_class": vehicle_class,
            "prompt_source": "TASK007_REAL_DETECTION",
            "detector_sha256": DETECTOR_SHA256,
            "prompt_count": len(prompt_results),
            "masks": masks,
            "overlay": overlay,
            "quality_observations": quality,
            "visual_review": {
                "decision": review["decision"],
                "notes": review["notes"],
            },
        })
        successful_classes.add(vehicle_class)
        sample_pss_bytes = int(segmentation["sampledPeakPssKb"]) * 1024
        peak_pss_bytes = max(peak_pss_bytes, sample_pss_bytes)
        per_image_metrics.append({
            "image_id": image_id,
            "detector_ms": captured["detector_inference_ms"],
            "encoder_ms": segmentation["imageEncoderMs"],
            "decoder_ms": sum(item["decoderMs"] for item in prompt_results),
            "total_ms": segmentation["totalMs"],
            "sampled_peak_pss_bytes": sample_pss_bytes,
        })

    if set(review_by_id) != {image["id"] for image in manifest.get("images", [])}:
        raise ValueError("visual reviews must correspond exactly to governed images")

    run = {
        "schema_version": RUN_SCHEMA,
        "candidate_id": "mobilesam-vit-t-box-prompt",
        "coordinate_contract_version": "iris-image-coordinate-v2",
        "device": {
            "manufacturer": "realme",
            "model": "RMX3780",
            "android_version": "15",
            "abi": "arm64-v8a",
            "emulator": False,
        },
        "model_identity": {
            "name": "MobileSAM ViT-T",
            "source_commit": "f706ad9c4eb7f219c00d9050e46328518ffb65d2",
            "upstream_checkpoint_sha256": "6dbb90523a35330fedd7f1d3dfc66f995213d81b29a5ca8108dbcdd4e37d6c2f",
            "license": "Apache-2.0",
        },
        "model_artifacts": model_entries,
        "evaluation_images": evaluation_images,
        "results": results,
        "claimed_supported_classes": sorted(successful_classes),
        "device_metrics": {
            "memory_metric": "sampled_process_pss",
            "peak_pss_bytes": peak_pss_bytes,
            "per_image": per_image_metrics,
        },
        "scope_note": (
            "Qualification is limited to car and motorcycle masks prompted by real TASK007 "
            "detections. It does not qualify other classes, damage classification, or production use."
        ),
    }
    (output / "run.json").write_text(
        json.dumps(run, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Assembled verified Android qualification package: {output}")


if __name__ == "__main__":
    main()
