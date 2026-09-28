# IRIS TASK 006 Classification Training Pipeline

Status: pipeline implemented; production training blocked.

Production classifier training has not occurred because no rights-cleared
accident-positive training samples are currently approved.

## Admission gate

The production manifest is `datasets/manifests/classification/manifest.v1.csv`.
Every admitted row must carry a stable item ID, binary label, source dataset
and version, source group/event identifiers, image path, SHA-256, dHash,
human label basis, approved rights status, split, and extraction metadata.
The source registry must also approve both source use and derived-data use.

The preflight gate checks files, SHA-256 values, class presence, required
group/event identifiers, approved rights, split validity, exact duplicates,
and cross-split dHash near duplicates. It refuses to train on missing classes,
missing groups, unapproved rights, missing files, hash drift, group leakage,
or duplicate leakage. It does not create rows or infer labels.

Run the current safe refusal from the repository root:

```powershell
py -3.13 ml/classification/scripts/train_classifier.py preflight
```

The current empty production manifest returns `BLOCKED` because there are no
approved accident-positive rows. The command exits nonzero and writes no
model, metrics, or successful-run artifact.

## Group splitting and leakage

`ml/classification/configs/split_policy.v1.json` defines the reproducibility
seed `6006` and group-based 70/15/15 train/validation/test targets. The split
unit is `source_group_id`, representing a physical event, source video, or
declared conservative leakage group. Image-level random splitting is not
allowed. Small datasets must have at least three independent groups per class
and sufficient class coverage for all three internal splits; otherwise the
pipeline blocks.

Exact SHA-256 duplicates may not cross splits. Available dHash values are
checked conservatively for near-duplicate cross-split leakage. A source group
must occur in only one split.

## Preprocessing

The default mobile input is 224x224 RGB. Images are decoded from their real
files, resized with aspect ratio preserved using bilinear `contain`, and
center-padded with black pixels. No crop is applied by default, so scene
content is not intentionally removed. Normalization uses ImageNet channel
mean `(0.485, 0.456, 0.406)` and standard deviation `(0.229, 0.224, 0.225)`.
Training augmentation is disabled until a conservative policy is validated;
validation and test preprocessing is deterministic.

## Model and reproducibility

The optional architecture path is MobileNetV3Small with one binary output.
The repository does not download weights. Initialization is explicit: random
initialization is the current configuration, or a locally supplied approved
checkpoint may be named later. PyTorch and torchvision are optional training
dependencies and are not required for dataset validation or the blocked
preflight.

The intended run records resolved configuration, manifest SHA-256, split
manifest, seed, preprocessing, training history, validation threshold,
held-out metrics, model metadata, and checksums. Failed or blocked runs do not
produce successful model artifacts.

## Thresholds and evaluation

The classifier emits a `model score`, not a calibrated probability or
confidence. A threshold is selected from validation predictions only by
maximum balanced accuracy, with deterministic tie handling. The test set is
held out until final evaluation. Metrics are computed only from actual
predictions: confusion counts, sensitivity/recall, specificity, precision,
F1, balanced accuracy, and ROC-AUC when both classes make it mathematically
valid. No placeholder metrics are stored.

Future TFLite/LiteRT export must record model SHA-256, input dimensions and
normalization, output semantics, threshold policy, manifest/version/hash,
evaluation references, and model version. A source-model/TFLite parity test is
required before any Android integration. No TFLite model is created by TASK
006 at this stage.
