# IRIS classification dataset tooling

This package prepares and validates a future real still-image dataset for the
binary labels `accident` and `non_accident`. It does not train a model and is
not used by the Flutter application.

## Environment

The reproducible project environment targets Python 3.10 with the single
pinned image dependency below. The 2026-09-27 acquisition checkpoint was also
validated with Python 3.13.7 and Pillow 11.1.0; use the pinned environment for
future repeatable runs:

```powershell
py -3.10 -m venv ml\classification\.venv
ml\classification\.venv\Scripts\python.exe -m pip install --requirement ml\classification\requirements-dataset.txt
```

Pillow performs full JPEG/PNG decoding, dimension inspection, and deterministic
64-bit dHash calculation. Manifest parsing, hashing, splitting, reporting, and
tests otherwise use the Python standard library. No ML framework is installed.

## Commands

Run from the repository root:

```powershell
py -3.10 -m unittest discover -s ml\classification\tests -t ml\classification -v
py -3.10 ml\classification\scripts\dataset_tool.py validate
py -3.10 ml\classification\scripts\dataset_tool.py report
```

The empty real manifest is expected to validate with zero errors but is not
training-eligible. AccidentDetection-9k and DATS_2022 candidate archives have
been acquired into ignored local storage, but every candidate remains pending
semantic review and no item has been promoted to the manifest. `report` must
therefore continue to show zero manifest items.

Inspect both official Mendeley archives, regenerate candidate inventories while
preserving source-matched decisions, and validate each inventory:

```powershell
py -3.10 ml\classification\scripts\dataset_tool.py inspect-mendeley
py -3.10 ml\classification\scripts\dataset_tool.py validate-reviews --review-inventory datasets\manifests\classification\accident_detection_9k_review.v1.csv
py -3.10 ml\classification\scripts\dataset_tool.py validate-reviews --review-inventory datasets\manifests\classification\dats_2022_review.v1.csv
```

To review a bounded DATS batch, extract it under ignored raw storage, enter only
real visual decisions in `review_batch.csv`, and apply it:

```powershell
py -3.10 ml\classification\scripts\dataset_tool.py create-review-batch --output-root datasets\raw\classification\review_batches\dats-v2-0000 --start 0 --limit 100
py -3.10 ml\classification\scripts\dataset_tool.py apply-review-batch --batch datasets\raw\classification\review_batches\dats-v2-0000\review_batch.csv
py -3.10 ml\classification\scripts\dataset_tool.py validate-reviews
```

The review tool never auto-labels DATS as `non_accident` or treats an
AccidentDetection box as a completed IRIS semantic review.

Inspect downloaded official DoTA metadata and, optionally, the frame tree:

```powershell
py -3.10 ml\classification\scripts\dataset_tool.py inspect-dota --metadata-root datasets\raw\classification\dota\official_repository\dataset --frames-root datasets\raw\classification\dota\official_frames
```

Extraction is intentionally blocked while the DoTA source, category, and
extraction policies are `REVIEW_REQUIRED`. Once rights and policies are
formally approved, every selected event must also have reviewed normal and
visible-collision windows. Detailed acquisition and pipeline instructions are
in [docs/CLASSIFICATION_DATASET.md](../../docs/CLASSIFICATION_DATASET.md).
