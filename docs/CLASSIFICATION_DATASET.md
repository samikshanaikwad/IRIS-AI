# TASK 006 Classification Dataset Policy

## Scope and current state

TASK 006 needs a real, provenance-preserving still-image dataset for a future
binary visual classifier. This checkpoint provides acquisition inspection,
versioned policies, deterministic source grouping, duplicate checks, review
inventories, validation, reporting, and tests.

Two real candidate-source archives are present locally in Git-ignored storage:
AccidentDetection-9k version 2 and DATS_2022 version 2. Acquisition does not
make an item training-eligible. All 11,852 candidate images remain pending
semantic review, AccidentDetection-9k has an unresolved underlying-image rights
limitation, and the production manifest remains header-only. No classifier has
been trained, evaluated, exported, or integrated into Flutter.

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

## Acquired Mendeley sources

The official source records are [AccidentDetection-9k version 2](https://data.mendeley.com/datasets/4x5my8gbcs/2)
(`10.17632/4x5my8gbcs.2`) and [DATS_2022 version 2](https://data.mendeley.com/datasets/nfc34n8svj/2)
(`10.17632/nfc34n8svj.2`). Both records declare CC BY 4.0 and exposed public,
unauthenticated downloads when inspected on 2026-09-27. Exact acquisition
metadata and citations are in `source_registry.v1.json`; measured archive and
content results are in `mendeley_source_inspection.v1.json`.

### AccidentDetection-9k

The official 606,678,399-byte archive has SHA-256
`707c932ef7b5a56a713d5f09713712016863793bcdae007d3ad90eba9503ae73`,
matching the hash published by Mendeley. Full inspection found:

- 9,002 readable JPEG images and no corrupt images, from 512×512 through
  640×640;
- publisher splits of 6,308 train, 1,801 validation, and 893 test images;
- 9,002 label files, including 8,853 images with syntactically valid class-0
  `Accident` boxes, 147 empty labels, and 2 images missing a corresponding
  label; two label files are orphaned;
- 9,859 total publisher bounding boxes;
- 339 exact-duplicate groups containing 700 images, including 171 groups that
  cross publisher splits; and
- 7,772 non-exact dHash candidate pairs at Hamming distance 4 or less,
  including 3,599 crossing publisher splits.

The 8,853 annotated/readable images are technical positive candidates, not
accepted IRIS labels. The publisher states that source images were found by
systematic Google image searches, and its README says underlying copyrights
remain with original creators. The record-level CC BY 4.0 declaration does not
independently prove reuse rights for every underlying web image. Consequently,
zero AccidentDetection images are rights-approved or semantically accepted for
training, and the publisher split is rejected for IRIS use.

### DATS_2022

The official bulk archive is 10,701,624,652 bytes. Its locally computed
SHA-256 is
`f4ffe186ea9d9c72e2f141e76c285b6b8740b0f4de672e58330b8a80ae36629f`.
Every ZIP member hash matches the multiset from the official per-file inventory:
10,245 files totaling 10,737,310,801 uncompressed bytes.

At interrupted-session recovery, 5,249,037,795 valid bytes already existed in
24 ranged parts. Each recovered range start and current tail matched the
official server. Resuming the missing 5,452,586,857 bytes was more efficient
than requesting the 2,850 image files individually, whose official sizes alone
total 10,730,373,278 bytes. No completed range was redownloaded.

The publication broadly describes more than 10,000 images, but the actual
version-2 inventory and archive contain 2,850 image files. All decode
successfully; decoded content is 2,845 JPEG and 5 PNG images, with dimensions
from 448×528 through 4624×4624. The archive also contains 7,394 JSON/TXT/XML
annotation files and one Windows shortcut. One TXT annotation is not in the
expected numeric object-detection row format. Observed object labels include
vehicles, people, traffic infrastructure, animals, and roadside objects; they
are object-detection metadata, not accident/non-accident labels.

DATS contains 46 exact-duplicate groups covering 92 images and 166 non-exact
dHash candidate pairs at Hamming distance 4 or less. Filename-derived sequence
identity is only partial. Camera timestamps and epoch-millisecond names are
grouped conservatively by day; numbered families stay together; unresolved
D-series and directory-only families are kept together. Exact and near
duplicates are then merged into the same leakage component. This reduces 38
base groups to 30 conservative groups; those groups may be refined only with
real provenance, never by assuming neighboring frames are independent.

All 2,850 images are candidate road-scene negatives pending visual review.
None is currently labelled `non_accident`, excluded, or in the production
manifest.

### Cross-source leakage

No exact content match was found between the two sources. The dHash scan found
12 cross-source candidate pairs across 3 conservative leakage groups. These are
review signals, not proof of identity; matched groups remain linked until a
human resolves them. A conflicting candidate is excluded or reviewed, never
assigned an arbitrary class.

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
official references and DOI/citation where available, inspected version,
separate code/content license fields, usage and redistribution status,
derived-data status, attribution, acquisition method and URLs, public-file
inventory, local path, checksums, suitability, and notes. Its schema identifier
is `iris-dataset-source-registry-v1`.

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

## Mendeley semantic-review workflow

`accident_detection_9k_review.v1.csv` and `dats_2022_review.v1.csv` are tracked
candidate inventories. They contain actual source path, technical/annotation
status, rights status, conservative group, SHA-256, dHash, decoded dimensions,
format, and explicit review fields. Inspection never infers a semantic label.
The allowed decisions are `pending`, `accident`, `non_accident`,
`exclude_ambiguous`, `exclude_visible_accident`, `exclude_irrelevant`, and
`exclude_corrupt`. Every non-pending decision requires a reviewer, review date,
and label basis. DATS cannot be accepted as `accident` through the negative
review flow, and AccidentDetection cannot be accepted as `non_accident`.

Run a deterministic local inspection and validate the inventories from the
repository root:

```powershell
py -3.10 ml\classification\scripts\dataset_tool.py inspect-mendeley
py -3.10 ml\classification\scripts\dataset_tool.py validate-reviews --review-inventory datasets\manifests\classification\accident_detection_9k_review.v1.csv
py -3.10 ml\classification\scripts\dataset_tool.py validate-reviews --review-inventory datasets\manifests\classification\dats_2022_review.v1.csv
```

Create an ignored visual-review batch without changing the master inventory,
record real decisions in the batch CSV while inspecting its extracted images,
then apply and validate it:

```powershell
py -3.10 ml\classification\scripts\dataset_tool.py create-review-batch --output-root datasets\raw\classification\review_batches\dats-v2-0000 --start 0 --limit 100
py -3.10 ml\classification\scripts\dataset_tool.py apply-review-batch --batch datasets\raw\classification\review_batches\dats-v2-0000\review_batch.csv
py -3.10 ml\classification\scripts\dataset_tool.py validate-reviews
```

Applying a batch persists only explicit decisions whose source item and
SHA-256 still match. Reinspection preserves valid prior decisions. Review
batches and extracted images remain ignored. Promotion of reviewed items into
the production manifest is deliberately deferred; this checkpoint adds zero
manifest rows.

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

For the Mendeley sources, publisher splits are informational only. IRIS starts
from filename-derived source families, merges exact and dHash-near components,
and links cross-source candidates. A future split must operate on those final
groups after semantic and rights review; it must not reuse the leaking
AccidentDetection split or randomly divide DATS video-derived neighbors.

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

datasets/raw/classification/accident_detection_9k/v2/
  Accident_Detection.zip     # Verified official archive
  README.md                  # Official source README

datasets/raw/classification/dats_2022/v2/
  DATS_2022.zip              # Verified against official member inventory
  inventory/                 # Official public-file metadata pages

datasets/raw/classification/review_batches/
  <batch>/                   # Temporary extracted images and decision CSV

datasets/derived/classification/
  dota/<event>/<label>/      # Future selected byte-preserving frames
```

Raw and derived contents are Git-ignored. Tracked READMEs, `.gitkeep` files,
policies, schemas, review CSVs, source registry, and manifests remain in Git.
Test images are generated only in temporary test directories.

## Acquisition status and blocked DoTA procedure

Both Mendeley archives were acquired without login from their official public
endpoints. AccidentDetection's four published files match the publisher's
SHA-256 values. Mendeley did not publish one bulk-archive hash for DATS, so IRIS
records its locally computed archive hash and additionally verifies every ZIP
member against the official per-file hash inventory. Raw archives are ignored
by Git.

DoTA is not being used for TASK 006 training and its approximately 55 GB frame
archive was not downloaded. The following procedure is retained only for a
future decision after dataset-content and derived-frame rights are clarified.

Any future DoTA acquisition requires explicit human action:

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

DoTA acquisition alone would not authorize extraction. After dataset-content and
derived-use permission is resolved, policy statuses are approved through a
reviewed change, and the two review CSVs are populated from real visual review,
the pipeline is:

```powershell
py -3.10 ml\classification\scripts\dataset_tool.py extract-dota --annotation-root datasets\raw\classification\dota\official_repository\dataset\annotations --source-root datasets\raw\classification\dota\official_frames --output-manifest datasets\manifests\classification\manifest.unsplit.csv
py -3.10 ml\classification\scripts\dataset_tool.py split --input-manifest datasets\manifests\classification\manifest.unsplit.csv --output-manifest datasets\manifests\classification\manifest.v1.csv --overwrite
py -3.10 ml\classification\scripts\dataset_tool.py validate
py -3.10 ml\classification\scripts\dataset_tool.py report
```

## Reporting and training gate

The report calculates real label/split/source/category/license counts, unique
source groups, per-group distribution, dimension ranges, duplicate findings,
missing/corrupt findings, validation totals, and training eligibility. With the
current empty manifest it truthfully reports zero items and no fabricated
statistics. The acquired candidate inventories do not count as manifest rows.

IndiaScene365 has not been acquired or assessed; it may be investigated only
if reviewed DATS data proves insufficient for negative diversity. DoTA remains
preserved as a blocked candidate rather than being downloaded or trained on.

No model training may begin until both classes contain genuinely accepted
items, rights status permits use, semantic review is complete, conservative
groups are split without leakage, and manifest validation reports zero errors.
