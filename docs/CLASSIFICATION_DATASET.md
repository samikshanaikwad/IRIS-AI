# TASK 006 Classification Dataset Policy

## Scope and current state

TASK 006 needs a real, provenance-preserving still-image dataset for a future
binary visual classifier. This checkpoint provides acquisition inspection,
versioned policies, deterministic frame selection, source-group splitting,
duplicate checks, validation, reporting, and tests.

No real training images are present. No classifier has been trained, evaluated,
exported, or integrated into Flutter. The header-only production manifest is
not training-eligible.

## Label contract

`accident` is permitted only when the still image itself contains visible
evidence consistent with an actual road-traffic collision or crash scene. A
source video eventually containing a crash is not enough.

`non_accident` is permitted only for a reviewed road/traffic/vehicle image with
no visible accident evidence. Unusual traffic, congestion, parked vehicles, and
night driving can be valid negatives when the individual image supports that
label.

The following remain excluded or require explicit policy review: imminent
collision before visible impact, near misses, reckless driving without a
collision, traffic violations, ambiguous pedestrian anomalies, emergency
response without visible crash evidence, later off-scene damage, racing and
crash-test imagery, rendered/simulated imagery, vehicle fire without visible
crash evidence, and non-road industrial accidents. Ambiguity is excluded rather
than forced into a binary class.

## DoTA investigation

Authoritative materials inspected on 2026-09-27:

- [Official DoTA repository](https://github.com/MoonBlvd/Detection-of-Traffic-Anomaly), inspected at commit `f8f603b8c06a946bc314752947ed480a4f33f82a`.
- [Official paper, arXiv:2004.03044](https://arxiv.org/abs/2004.03044).
- Download links published in the official repository README.

The inspected official annotation archive contains 4,677 per-clip JSON files.
Each annotation includes the clip/event name, frame count, ignore flag,
ego-involvement and night flags, anomaly and video bounds, accident ID/name,
and per-frame labels containing frame ID, image path, accident metadata, and
objects. Of those 4,677 annotations, 61 carry the official `ignore=true` flag;
the IRIS inspector reports them and the extractor excludes them. Official
metadata contains 3,275 train clips and 1,402 validation clips.

The paper reports 731,932 extracted frames at 10 frames per second and
1280×720. The official README advertises either one approximately 55 GB frame
archive or a split download of five approximately 10 GB parts and one
approximately 5 GB part. The large frame archive was not downloaded during
this checkpoint.

DoTA clip IDs end with a six-digit clip-start suffix. Removing that suffix
identifies the originating video for the inspected metadata. There are 190
such source videos, and 177 occur on both sides of the official clip-level
train/validation split. IRIS therefore must not reuse that split: all clips and
frames from one original source video stay in one IRIS split.

The official paper explains that `anomaly_start` marks when an anomaly becomes
inevitable. It can therefore precede visible impact and cannot by itself define
an `accident` still image.

### Category policy

The paper describes nine base anomaly categories with ego/non-ego variants.
The inspected annotation archive uses IDs 1–10 because leaving the roadway to
the right and left are separate IDs. The complete per-viewpoint mapping is in
`ml/classification/configs/dota_category_policy.v1.json`:

| IDs | Official annotation meaning | IRIS action |
|---|---|---|
| 1–7 | start/stop/stationary, moving ahead/waiting, lateral, oncoming, turning, pedestrian, or obstacle collision | `INCLUDE_ACCIDENT`, but only inside a human-reviewed visible-collision window |
| 8–9 | leave roadway right/left | `EXCLUDE_AMBIGUOUS` because leaving the road does not prove a visible collision |
| 10 | unknown anomaly | `REVIEW_REQUIRED` |

Both ego and non-ego forms are represented, yielding 14 conditional include,
4 ambiguous exclusion, and 2 review-required mappings. A reviewed pre-event
normal region can be a `POSSIBLE_NON_ACCIDENT_SOURCE`; it is not automatically
normal merely because it occurs before `anomaly_start`.

### Usage and licensing status

The official repository carries an MIT software license. Its README says the
authors contacted original channel authors and obtained authority to share the
downloaded clips. The inspected official materials did not contain a separate
dataset-content license or explicit terms for locally derived training frames.
The software license is therefore not treated as a video-content license.

DoTA remains `REVIEW_REQUIRED` for source use, redistribution, and derived
data. Extraction refuses to run until those statuses and the two policy
statuses are formally approved. The unresolved question is whether the
applicable permissions allow IRIS to create and use local derived stills under
the intended project conditions.

The Google Drive URLs were present in the inspected official README. The large
archives were not downloaded, so current end-to-end download completion,
archive filenames, archive checksums, and extracted contents were not verified.
The official instructions do not describe dataset-specific credentials;
ordinary Google Drive browser sign-in, quota, or confirmation may still be
required.

## Source registry and manifest

`datasets/manifests/classification/source_registry.v1.json` records dataset ID,
official references, inspected version, separate code/content license fields,
usage and redistribution status, derived-data status, attribution, acquisition
method, local path, locally computed metadata checksums, suitability, and
notes. Its schema identifier is `iris-dataset-source-registry-v1`.

`manifest.v1.csv` uses `iris-classification-manifest-v1`. Required provenance
and integrity fields include item/path, label/split, dataset and version,
source group/event/video, label basis, license status, SHA-256, 64-bit dHash,
extraction version, and dimensions. Optional genuine metadata includes source
frame/timestamp/reference/category, day/night, weather, ego involvement, and
accident category. Unavailable optional values remain empty; they are never
invented.

`source_timestamp_ms` for DoTA is deterministically clip-relative from the
official 10 fps representation. It is not represented as an original recording
wall-clock time.

## Review and temporal safety

The versioned extraction policy is `iris-dota-frame-extraction-v1` and remains
`REVIEW_REQUIRED`. Its proposed initial values are:

- source rate: 10 frames/second;
- pre-event exclusion buffer: 20 frames (2 seconds);
- reviewed normal window required;
- reviewed visible-collision window required;
- post-event normal selection disabled;
- minimum selected-frame spacing: 10 frames (1 second);
- maximum per event: 3 accident and 3 non-accident frames;
- copy mode: byte-preserving.

The 20-frame buffer is a conservative, configurable starting policy, not a
scientifically optimal universal value. `dota_normal_windows.v1.csv` records a
human-reviewed range that contains no visible accident evidence and must end
before the buffer. `dota_visible_windows.v1.csv` records a human-reviewed
collision-visible range inside the official anomaly interval. Both require a
review version, reviewer, review date, and rationale. Missing reviews cause the
corresponding label to be skipped, never guessed.

Sampling is deterministic, bounded, and temporally spaced. Selected image
bytes are copied without resizing or recompression; model preprocessing is a
future training concern. Each output receives a full-byte SHA-256, decoded
dimensions, and dHash.

## Split policy and leakage prevention

The fixed split seed is `6006`. Target allocations are 70% train, 15%
validation, and 15% internal test by `source_group_id`, with best-effort
stratification by source dataset and source category. Exact row counts are not
promised, and event/video grouping takes priority over perfect balance.

For DoTA, `source_group_id` represents the original source video, which is
stricter than grouping only one extracted clip. Every row from that group must
share one split. `external_test` is preserved separately and must never be used
for training, threshold selection, or tuning.

The validator rejects source-group leakage and exact duplicates across splits.
It also rejects invalid labels/splits, missing provenance, unapproved usage,
version mismatches, unsafe paths, missing/zero/corrupt/unsupported images,
malformed indices, dimension/hash mismatches, duplicate IDs/paths, and unknown
extraction versions.

Exact content identity uses SHA-256. Candidate near duplicates use a
deterministic 64-bit difference hash: decode to grayscale, resize to 9×8 with
Lanczos, compare each horizontal neighbor, and compare hashes by Hamming
distance. The default review radius is 4 bits. A same-split candidate is a
warning; a cross-split candidate is an error. dHash similarity is a review
signal, not proof of identity.

## Local layout and Git policy

```text
datasets/raw/classification/dota/
  official_repository/
    dataset/                 # Official metadata and extracted annotations
  official_frames/
    frames/<event>/images/   # Extracted official frame archive layout

datasets/derived/classification/
  dota/<event>/<label>/      # Future selected byte-preserving frames
```

Raw and derived contents are Git-ignored. Tracked READMEs, `.gitkeep` files,
policies, schemas, review CSVs, source registry, and manifests remain in Git.
Test images are generated only in temporary test directories.

## Acquisition procedure

Large downloads require explicit human action:

1. Open the [official repository](https://github.com/MoonBlvd/Detection-of-Traffic-Anomaly) and acquire the repository at the inspected commit into `datasets/raw/classification/dota/official_repository/`.
2. Confirm that `dataset/DoTA_annotations.zip`, `dataset/metadata_train.json`, `dataset/metadata_val.json`, and `dataset/DoTA_urls.txt` are present. Their locally computed SHA-256 values at the inspected commit are recorded in the source registry and checked by `inspect-dota`.
3. In the official README, choose either the [single approximately 55 GB frame archive](https://drive.google.com/file/d/1RQp4hOP9X7TW6S3_vbqZvFSkrbbFzrRj/view?usp=sharing) or all six files in the [official split-archive folder](https://drive.google.com/drive/folders/1_WzhwZC2NIpzZIpX7YCvapq66rtBc67n). Preserve official names. Browser/Google Drive interaction may be required; do not use unofficial mirrors or bypass access controls.
4. Extract the frame archive so the local path is `datasets/raw/classification/dota/official_frames/frames/<source_event_id>/images/<frame>.jpg`.
5. Extract `dataset/DoTA_annotations.zip` so JSON files are available at `official_repository/dataset/annotations/`.
6. Run the inspection command below. It verifies the inspected metadata files and checks all 4,677 event directories when `--frames-root` is supplied.

```powershell
py -3.10 ml\classification\scripts\dataset_tool.py inspect-dota --metadata-root datasets\raw\classification\dota\official_repository\dataset --frames-root datasets\raw\classification\dota\official_frames
```

The repository also links an [official folder for six removed-source originals](https://drive.google.com/drive/folders/1uSdyNu8XM_QV6y9r4tpxN7iNNNAgWy9P?usp=sharing). Do not acquire or use those separately unless provenance and rights review establishes they are needed.

Acquisition alone does not authorize extraction. After dataset-content and
derived-use permission is resolved, policy statuses are approved through a
reviewed change, and the two review CSVs are populated from real visual review,
the pipeline is:

```powershell
py -3.10 ml\classification\scripts\dataset_tool.py extract-dota --annotation-root datasets\raw\classification\dota\official_repository\dataset\annotations --source-root datasets\raw\classification\dota\official_frames --output-manifest datasets\manifests\classification\manifest.unsplit.csv
py -3.10 ml\classification\scripts\dataset_tool.py split --input-manifest datasets\manifests\classification\manifest.unsplit.csv --output-manifest datasets\manifests\classification\manifest.v1.csv --overwrite
py -3.10 ml\classification\scripts\dataset_tool.py validate
py -3.10 ml\classification\scripts\dataset_tool.py report
```

## Reporting and future sources

The report calculates real label/split/source/category/license counts, unique
source groups, per-group distribution, dimension ranges, duplicate findings,
missing/corrupt findings, validation totals, and training eligibility. With the
current empty manifest it truthfully reports zero items and no fabricated
statistics.

A future approved BDD100K or comparable source may add challenging independent
normal-driving negatives. A future independently sourced dataset such as
DADA-2000 may be considered only for `external_test`. Neither source is
approved or acquired by this checkpoint.

No model training may begin until real data is acquired legally, all semantic
review is complete, the grouped split is produced, and validation reports zero
errors.
