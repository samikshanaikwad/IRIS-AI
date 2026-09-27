# IRIS datasets

This directory contains version-controlled dataset policy and manifests, not
training imagery. IRIS user evidence and manual-acceptance images must never be
copied into the training dataset.

## Layout

```text
datasets/
  raw/classification/          # Local acquired source material; Git-ignored
  derived/classification/      # Local byte-preserving stills; Git-ignored
  manifests/classification/    # Tracked schemas, registry, reviews, manifest
```

Only documentation and `.gitkeep` files under `raw/` and `derived/` are
tracked. The current classification manifest contains its header only: no real
dataset has been acquired, derived, or approved for training.

The source registry is the authority for dataset provenance and usage status.
A repository code license must never be treated as a dataset-content license.
See [the classification dataset policy](../docs/CLASSIFICATION_DATASET.md) for
the label, acquisition, review, split, validation, and reporting rules.
