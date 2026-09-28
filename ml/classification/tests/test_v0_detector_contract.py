import json
from pathlib import Path

from ml.classification.scripts.validate_v0_detector_contract import validate


ROOT = Path(__file__).resolve().parents[3]
CONTRACT = ROOT / "datasets/manifests/detection/v0_object_detector_contract.v1.json"


def test_contract_has_required_road_classes_and_truthful_status():
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    assert contract["status"] == "QUALIFIED_WITH_RESTRICTIONS"
    assert contract["label_map"]["required_road_classes"] == {
        "person": 0,
        "bicycle": 1,
        "car": 2,
        "motorcycle": 3,
        "bus": 5,
        "truck": 7,
    }
    assert contract["output"]["scores"]["meaning"] == "detection score, not a calibrated probability"


def test_real_qualification_artifact_validates_when_present():
    artifact = ROOT / "ml/runs/detection/v0-efficientdet-lite0-qualification/efficientdet_lite0_detection_metadata_1.tflite"
    if not artifact.exists():
        return
    validate(CONTRACT, artifact)
