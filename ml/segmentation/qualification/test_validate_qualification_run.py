import json
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
                "offline_android_path": "test-only", "decision": "BLOCKED",
                "blockers": ["test-only"],
            }],
        }), encoding="utf-8")

    def test_inventory_validation_is_not_qualification(self):
        inventory = validate_inventory(self.inventory_path)
        self.assertEqual(inventory["candidates"][0]["decision"], "BLOCKED")

    def test_synthetic_image_cannot_qualify(self):
        artifact = self.root / "model.onnx"
        artifact.write_bytes(b"model fixture")
        image = self.root / "image.png"
        image.write_bytes(b"image fixture")
        import hashlib
        run = {
            "schema_version": "iris-segmentation-qualification-run-v1",
            "candidate_id": "candidate",
            "coordinate_contract_version": "iris-image-coordinate-v2",
            "device": {"manufacturer": "test", "model": "test", "android_version": "test", "abi": "test", "emulator": False},
            "model_artifacts": [{"path": artifact.name, "sha256": hashlib.sha256(artifact.read_bytes()).hexdigest()}],
            "evaluation_images": [{"id": "image", "path": image.name, "sha256": hashlib.sha256(image.read_bytes()).hexdigest(), "synthetic": True, "rights_status": "CLEARED", "source": "test-only", "license_or_permission": "test-only"}],
            "results": [], "claimed_supported_classes": [],
            "device_metrics": {"inference_ms": [1], "peak_rss_bytes": 1},
        }
        run_path = self.root / "run.json"
        run_path.write_text(json.dumps(run), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Synthetic|synthetic"):
            validate_run(validate_inventory(self.inventory_path), run_path)


if __name__ == "__main__":
    unittest.main()
