import json
import hashlib
import tempfile
import unittest
from pathlib import Path

from validate_qualification_run import validate_inventory, validate_run


class QualificationGateTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.inventory_path = self.root / "candidates.json"
        self.inventory_path.write_text(json.dumps({
            "schema_version": "iris-segmentation-candidate-inventory-v1",
            "required_vehicle_classes": ["bicycle", "car", "motorcycle", "bus", "truck"],
            "candidates": [{
                "id": "candidate", "capability": "test-only fixture",
                "official_source": "https://example.invalid/official",
                "license": "test-only", "class_contract": "test-only",
                "offline_android_path": "test-only", "decision": "QUALIFIED",
                "blockers": ["test-only"],
            }],
        }), encoding="utf-8")

    def test_inventory_validation_records_candidate_decision(self):
        inventory = validate_inventory(self.inventory_path)
        self.assertEqual(inventory["candidates"][0]["decision"], "QUALIFIED")

    def test_synthetic_image_cannot_qualify(self):
        artifact = self.root / "model.onnx"
        artifact.write_bytes(b"model fixture")
        image = self.root / "image.png"
        image.write_bytes(b"image fixture")
        run = {
            "schema_version": "iris-segmentation-qualification-run-v1",
            "candidate_id": "candidate",
            "coordinate_contract_version": "iris-image-coordinate-v2",
            "device": {"manufacturer": "test", "model": "test", "android_version": "test", "abi": "test", "emulator": False},
            "model_artifacts": [{"path": artifact.name, "sha256": hashlib.sha256(artifact.read_bytes()).hexdigest()}],
            "evaluation_images": [{"id": "image", "path": image.name, "sha256": hashlib.sha256(image.read_bytes()).hexdigest(), "synthetic": True, "rights_status": "CLEARED", "source": "test-only", "license_or_permission": "test-only"}],
            "results": [], "claimed_supported_classes": [],
            "device_metrics": {
                "memory_metric": "sampled_process_pss",
                "peak_pss_bytes": 1,
                "per_image": [],
            },
        }
        run_path = self.root / "run.json"
        run_path.write_text(json.dumps(run), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Synthetic|synthetic"):
            validate_run(validate_inventory(self.inventory_path), run_path)

    def _write_valid_run(self):
        artifact = self.root / "model.onnx"
        artifact.write_bytes(b"model fixture")
        image = self.root / "image.png"
        image.write_bytes(b"rights-cleared image fixture")
        mask = self.root / "mask.png"
        mask.write_bytes(b"real-run mask fixture")
        overlay = self.root / "overlay.png"
        overlay.write_bytes(b"real-run overlay fixture")

        def entry(path):
            return {
                "path": path.name,
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            }

        run = {
            "schema_version": "iris-segmentation-qualification-run-v1",
            "candidate_id": "candidate",
            "coordinate_contract_version": "iris-image-coordinate-v2",
            "device": {
                "manufacturer": "realme",
                "model": "RMX3780",
                "android_version": "15",
                "abi": "arm64-v8a",
                "emulator": False,
            },
            "model_artifacts": [entry(artifact)],
            "evaluation_images": [{
                "id": "image",
                **entry(image),
                "synthetic": False,
                "rights_status": "CLEARED",
                "source": "https://example.invalid/rights-cleared",
                "license_or_permission": "test fixture permission",
            }],
            "results": [{
                "image_id": "image",
                "status": "SUCCESS",
                "vehicle_class": "car",
                "prompt_source": "TASK007_REAL_DETECTION",
                "detector_sha256": "2e04c53bfeac0ac2a30c057c7e2a777594ce39baaac35a92f74fb1e8c4fc4e0b",
                "prompt_count": 1,
                "masks": [entry(mask)],
                "overlay": entry(overlay),
                "visual_review": {"decision": "ACCEPTED", "notes": "Aligned fixture output."},
            }],
            "claimed_supported_classes": ["car"],
            "device_metrics": {
                "memory_metric": "sampled_process_pss",
                "peak_pss_bytes": 512 * 1024 * 1024,
                "per_image": [{
                    "image_id": "image",
                    "detector_ms": 50,
                    "encoder_ms": 2500.0,
                    "decoder_ms": 200.0,
                    "total_ms": 7000.0,
                    "sampled_peak_pss_bytes": 512 * 1024 * 1024,
                }],
            },
        }
        run_path = self.root / "run.json"
        run_path.write_text(json.dumps(run), encoding="utf-8")
        return run_path

    def test_real_prompt_masks_and_measured_pss_can_pass(self):
        validate_run(validate_inventory(self.inventory_path), self._write_valid_run())

    def test_success_rejects_unmeasured_rss_substitution(self):
        run_path = self._write_valid_run()
        run = json.loads(run_path.read_text(encoding="utf-8"))
        run["device_metrics"] = {"inference_ms": [7000], "peak_rss_bytes": 1}
        run_path.write_text(json.dumps(run), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "sampled process PSS"):
            validate_run(validate_inventory(self.inventory_path), run_path)

    def test_success_rejects_non_detector_prompt(self):
        run_path = self._write_valid_run()
        run = json.loads(run_path.read_text(encoding="utf-8"))
        run["results"][0]["prompt_source"] = "MANUAL_BOX"
        run_path.write_text(json.dumps(run), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "TASK007"):
            validate_run(validate_inventory(self.inventory_path), run_path)

    def test_blocked_candidate_cannot_pass_a_real_run(self):
        run_path = self._write_valid_run()
        inventory = json.loads(self.inventory_path.read_text(encoding="utf-8"))
        inventory["candidates"][0]["decision"] = "BLOCKED"
        self.inventory_path.write_text(json.dumps(inventory), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "qualified candidate"):
            validate_run(validate_inventory(self.inventory_path), run_path)


if __name__ == "__main__":
    unittest.main()
