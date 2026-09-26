# Deterministic Evidence Quality Assessment

TASK 005 adds offline technical validation for real managed evidence images. It checks whether IRIS can read and decode the stored original, verifies its import-time SHA-256, and reports transparent pixel measurements. It does not use machine learning and does not determine whether an accident occurred, what caused it, or whether reconstruction is possible.

## Algorithm identity and inputs

- Algorithm version: `iris-image-quality-v1`
- Integrity input: the complete managed original byte stream
- Original resolution input: dimensions reported by Flutter's image descriptor for the encoded original
- Metric input: a decoded RGBA image whose longest edge is at most 1024 pixels, with aspect ratio preserved
- Execution: one explicitly requested evidence assessment at a time; case summaries validate persisted-result freshness sequentially without decoding image batches

Flutter's bundled offline image codec is used, so this feature introduces no package or native plugin. The managed original is opened read-only. IRIS never resizes, recompresses, rotates, annotates, replaces, or updates metadata in that file. Downsampled pixels exist only as an in-memory analysis representation.

## Measurements and thresholds

All values below are centralized in `EvidenceQualityThresholds`. They are initial IRIS application thresholds, not universal scientific or forensic standards. They require later calibration against representative incident-scene imagery before production forensic use.

| Check | Version 1 calculation | Initial IRIS threshold |
|---|---|---|
| Resolution | Original decoded width, height, and pixel count | Warning when short edge is under 720 px or area is under 921,600 pixels |
| Sharpness | Variance of the four-neighbor Laplacian `4C - left - right - up - down` over interior pixels in the bounded luma image | Warning below 100.0 Laplacian-variance units |
| Mean brightness | Mean BT.709 luma, `Y = 0.2126R + 0.7152G + 0.0722B` | Dark warning below 50.0; bright warning above 205.0 on a 0–255 scale |
| Dark clipping | Fraction of analyzed pixels with luma at or below 10.0 | Warning when fraction is at least 0.20 (20%) |
| Bright clipping | Fraction of analyzed pixels with luma at or above 245.0 | Warning when fraction is at least 0.20 (20%) |
| Orientation | Comparison of original decoded width and height | Width greater than height: landscape; height greater than width: portrait; equal: square |

Resolution and orientation always use original decoded dimensions. Sharpness, brightness, and clipping use the bounded representation. SHA-256 always covers every byte of the complete managed original. Metric loops run outside the UI isolate after bounded decode.

## Integrity and readiness

IRIS streams the current managed file through SHA-256 and compares the result with the immutable digest recorded at TASK 004 import. A mismatch is critical: it is displayed, persisted, and makes the evidence `Not usable`. IRIS does not overwrite the import-time digest, delete the evidence, or offer a control that silently blesses changed bytes.

Readiness is deterministic:

- `Ready`: the file is readable, decodes, its SHA-256 is verified, metric computation succeeds, and no configured warning is triggered.
- `Usable with limitations`: the file is readable and verified but one or more quality warnings are present, such as low resolution, possible blur, unusual mean brightness, or significant clipping.
- `Not usable`: the managed file is missing or unreadable, decode or metric computation fails, or SHA-256 mismatches.
- `Not assessed`: no real assessment has been persisted for this evidence.

`Ready` means only that these configured technical checks found no warning. It is not accident confirmation, reconstruction sufficiency, forensic validation, or AI confidence. Darkness is a limitation rather than grounds to discard otherwise readable, verified evidence.

## Schema version 3 and migration

The non-destructive v2-to-v3 migration adds `evidence_quality_assessments` with one latest assessment per evidence ID. It stores assessment time, algorithm version, expected and assessed SHA-256 values, file/decode/integrity/readiness states, measured file size, original and analysis dimensions, orientation, numeric metrics, and typed findings serialized as local JSON. Nullable columns represent genuinely unavailable measurements; migration inserts no assessment rows.

The assessment row references `evidence_images(id)` with `ON DELETE CASCADE`. Evidence deletion removes its assessment, and case deletion cascades through evidence to assessments without affecting another case. Existing cases, evidence paths, metadata, and import-time hashes are preserved.

Persisted results are current only when the algorithm version and expected import hash still match and a fresh full-file SHA-256 matches the digest measured by that assessment. Otherwise the UI reports that reassessment is needed and does not present stale metrics as current. Existing v2 evidence therefore starts as `Not assessed` and can be analyzed without re-import.

## Workflow and failures

Acquisition remains durable and independent: a successful import is persisted before quality assessment. The user starts the first assessment or a reassessment from Evidence Detail. The UI uses real indeterminate progress and prevents duplicate submissions. Calculation failure preserves the original and creates no pretend result; persistence failure states that the calculated assessment could not be saved. A damaged image does not prevent another evidence item from being assessed.

## Known limitations

- Version 1 uses general-purpose technical thresholds that are not calibrated as forensic acceptance criteria.
- Variance of Laplacian is content- and scale-dependent; low-texture scenes can produce low values without camera blur.
- Mean luma and clipping summarize the bounded full frame and do not identify locally important regions.
- Codec support depends on image formats supported by the bundled Flutter/Android codec.
- No EXIF orientation inference, incident classification, object/damage detection, reconstruction, physics, scenario analysis, or forensic chain-of-custody workflow is implemented.
