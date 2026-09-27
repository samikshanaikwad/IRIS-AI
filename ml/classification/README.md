# IRIS classification dataset tooling

This package prepares and validates a future real still-image dataset for the
binary labels `accident` and `non_accident`. It does not train a model and is
not used by the Flutter application.

## Environment

Python 3.10 is the validated local interpreter. Use a project-local virtual
environment and the single pinned image dependency:

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
training-eligible. `report` must show zero real items until legitimate data is
acquired and derived.

Inspect downloaded official DoTA metadata and, optionally, the frame tree:

```powershell
py -3.10 ml\classification\scripts\dataset_tool.py inspect-dota --metadata-root datasets\raw\classification\dota\official_repository\dataset --frames-root datasets\raw\classification\dota\official_frames
```

Extraction is intentionally blocked while the DoTA source, category, and
extraction policies are `REVIEW_REQUIRED`. Once rights and policies are
formally approved, every selected event must also have reviewed normal and
visible-collision windows. Detailed acquisition and pipeline instructions are
in [docs/CLASSIFICATION_DATASET.md](../../docs/CLASSIFICATION_DATASET.md).
