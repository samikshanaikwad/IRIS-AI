# TASK 006 Accident-Positive Dataset Qualification

**Research checkpoint:** 2026-09-28
**Scope:** source qualification only. No candidate from this document has been
added to the IRIS production classification manifest, and no model has been
trained or integrated.

## Qualification rule

IRIS evaluates source-content rights separately from code licenses, from
permission to create local stills, and from the semantic suitability of an
individual still. A source can be acceptable for academic training while still
requiring restrictions on redistribution, source-sequence grouping, and human
visual selection. A video-level "positive" label never automatically becomes
an IRIS `accident` still label: the individual frame must visibly show a road
collision, rollover, or clearly accident-damaged road-vehicle context.

The categories below are project controls, not legal advice:

- `QUALIFIED`: authoritative terms support the intended research use without a
  material source-rights restriction.
- `QUALIFIED_WITH_RESTRICTIONS`: authoritative terms support academic training,
  but specific use, redistribution, attribution, or semantic constraints must
  be obeyed.
- `REVIEW_REQUIRED`: a material permission, provenance, or still-labeling
  question has not been resolved.
- `REJECTED`: IRIS will not use the candidate under its current documented
  provenance, even if a host page displays a license label.

All source records, terms, and access state below were inspected on
2026-09-28. No rights are inferred where the authoritative source is silent.

## Qualification table

| Candidate | Authoritative source and publisher | Media / scale / grouping | Content rights and downstream status | Still-image suitability | IRIS status |
| --- | --- | --- | --- | --- | --- |
| **TUM Traffic Accid3nD (TUMTraf-Accid3nD)** | [Official TUM project](https://accident-dataset.github.io/), Zimmer et al.; [paper](https://arxiv.org/abs/2503.12095) | First-party roadside camera/LiDAR collection at the A9 Digital Test Field, Munich. Project reports 111,945 labeled frames, four cameras plus LiDAR at 25 Hz, 2,634,233 labels, and OpenLABEL. Official WebDAV metadata lists five ZIP archives totaling 46,587,516,755 bytes. Sequences/events and multi-camera views must be indivisible groups after acquisition. | The source-specific project page says **CC BY-NC-SA 4.0**, but the official generic TUMTraf development-kit README says **CC BY-NC-ND 4.0**. That conflict is material: IRIS does not infer derived-still, training, redistribution, or model-release permission until TUM confirms the terms governing Accid3nD. The development kit's MIT license applies to code only. | Strong positive provenance: project-recorded real collisions, rollovers, and fires. Frames need human selection because pre-event/transition frames do not establish a visible accident; possible negatives require separate review. | **REVIEW_REQUIRED** |
| **ACCIDENT benchmark** | [Official project page](https://accidentbench.github.io/), [official code/data instructions](https://github.com/accidentbench/ACCIDENT), Picek et al., CVPR Workshops 2026 | Traffic-surveillance video benchmark: 2,027 real clips and 2,211 CARLA-generated synthetic clips. The real clips are heterogeneous online CCTV sources; the official repository downloads a Kaggle archive (`picekl/accident`) containing `real_videos/`, metadata, and optionally synthetic data. The official source does not publish an accessible archive byte size; Kaggle CLI authentication is required. | The official supplemental policy says only clips whose upstream licenses explicitly permit redistribution and derivative works were included, with canonical source URLs in metadata. Annotations/metadata are CC BY 4.0; code and CARLA assets are Apache-2.0. Use is restricted to research and re-identification is prohibited. This supports local research use of licensed clips, but does not itself settle every upstream clip’s exact terms or permission to distribute an IRIS-trained/TFLite model. | Real clips have accident time, spatial location, and collision type. Accident-visible frame extraction is technically feasible, but IRIS must select only frames where the still visibly supports `accident`; pre-impact/ambiguous frames are excluded. Video IDs/metadata provide a practical event-group key, subject to verification after authorized acquisition. Synthetic clips are not substitutes for real accident evidence. | **REVIEW_REQUIRED** |
| **Nexar Collision Prediction Dataset** | [Official Nexar Hugging Face record](https://huggingface.co/datasets/nexar-ai/nexar_collision_prediction), Nexar Inc.; [dataset paper](https://arxiv.org/abs/2503.03848); [dataset license](https://huggingface.co/datasets/nexar-ai/nexar_collision_prediction/blob/main/LICENSE) | Nexar dashcam video: 1,500 1280x720, 30 fps videos, typically about 40 seconds; official repository reports 31.4 GB. Half are event-positive and half regular driving. One video ID must be one split group; frames may not be randomly split. | Copyright 2025 Nexar Inc. The Nexar Open Data License explicitly permits use, copying, modification, and distribution with required attribution/notices; it prohibits resale/profit redistribution and imposes ethical/privacy restrictions. Access is gated: an account must agree to share contact information and accept the terms. The license does not expressly address trained-model distribution, so that remains a release review item. | Useful positives only after visual selection: the source treats actual collisions **and near-misses/imminent collisions** as positive. IRIS excludes the latter from `accident`. Regular-driving videos are negative candidates only after individual-frame review. | **QUALIFIED_WITH_RESTRICTIONS** |
| **DADA-2000 / DADA** | [Official author repository](https://github.com/JWFangit/LOTVS-DADA); Fang et al., [paper](https://arxiv.org/abs/1912.03077) | Crowdsourced accident-scenario video. The paper reports 2,000 clips, about 658,476 frames, 54 accident types, temporal accident windows, and spatial crash-object annotations. The author repository advertises roughly 53 GB compressed training/test data and roughly 116 GB compressed full data through Drive/Baidu links. Clip ID is an appropriate future group. | The author repository invites use/share and asks for paper citation, but it has no published dataset-content license and gives no explicit permission for training, derived frames, source-media redistribution, or trained-model distribution. No download was attempted. | Temporal accident context is not a still label. Accident-visible windows could be reproducibly proposed from annotations, then reviewed. Pre-impact and precursor frames cannot automatically become either class. | **REVIEW_REQUIRED** |
| **DoTA** | [Official repository](https://github.com/MoonBlvd/Detection-of-Traffic-Anomaly), inspected at commit `f8f603b8c06a946bc314752947ed480a4f33f82a`; [paper](https://arxiv.org/abs/2004.03044) | YouTube-derived traffic anomaly clips; official metadata has 4,677 clips and describes approximately 55 GB of extracted frames. Original source-video grouping is recoverable and must replace the publisher clip split. | The repository's MIT text is a **code** license. The README says the authors obtained authority from original channel authors to share clips, but current official README/repository/issue inspection supplied no separate content license or explicit local derived-frame/training/model-distribution terms. No new clarification was found; an unanswered or closed issue is not permission. | The anomaly start can precede visible impact, so frames require a reviewed collision-visible window. Some anomaly types are not collisions. | **REVIEW_REQUIRED** |
| **AccidentDetection-9k v2** | [Official Mendeley record](https://data.mendeley.com/datasets/4x5my8gbcs/2), DOI `10.17632/4x5my8gbcs.2` | Locally acquired/inspected: 9,002 readable images; 8,853 technical `Accident` annotation candidates. Extensive exact and perceptual duplicates cross its publisher splits. | The record declares CC BY 4.0, but the publisher says imagery was collected through Google image search and its README retains rights with original creators/rightsholders. The record does not independently establish rights for each web image. | Bounding-box annotation does not replace IRIS visible-accident review; technical candidates remain pending. | **REVIEW_REQUIRED** |
| **Dataset Klasifikasi Kecelakaan** (Roboflow) | [Roboflow Universe record](https://universe.roboflow.com/asraf/dataset-klasifikasi-kecelakaan), uploader shown as Asraf | Record exposes accident/no-accident classification, 6,279 images and two versions. No data was downloaded; no original non-Roboflow publisher was located. | The page displays CC BY 4.0, but provides no documented ownership, original image sources, chain of rights, or evidence that the uploader originated the media. A host-level label alone is insufficient for IRIS. | Its binary labels and duplicate/leakage properties cannot be trusted without source provenance and direct inspection. | **REJECTED** |
| **CCTV Traffic Accident Object Detection Dataset** | [Hugging Face derivative](https://huggingface.co/datasets/justjuu/traffic-accident-cctv-object-detection), uploader `justjuu`; [original Roboflow record](https://universe.roboflow.com/accident-and-nonaccident/accident-and-non-accident-label-image-dataset), publisher `Accident and Nonaccident` | HF card reports 1,485 unique CCTV frames, approximately 3,000 expanded rows, 640x640 letterboxed images, COCO-style boxes, and a current viewer total of 2,763 rows / 1.01 GB. The derivative is split into train/validation/test and contains image/object records, but no disclosed source video, camera, event, or timestamp identifiers. | HF declares **CC0-1.0** and says the original was designated Public Domain. The original Roboflow record says **Public Domain**. Neither page documents who owns or captured the underlying CCTV media, upstream URLs, releases, or authority to dedicate third-party material to the public domain. The HF declaration cannot cure an unresolved upstream rights chain. | Object annotations define `accident` regions and `non_accident` regions; one frame may contain both. Accident boxes can identify image-level positive candidates for human review, but a non-accident box never proves the whole image is non-accident. The card describes offline resize/padding, flips, and brightness augmentation; it does not provide a reliable original-to-derivative mapping. | **REVIEW_REQUIRED** |

## Rights and provenance findings

### TUMTraf-Accid3nD

This remains the strongest currently located first-party academic positive
source by provenance, but it is not currently acquisition-approved by IRIS.
The official project says its own roadside sensors recorded real highway
accidents, which resolves the web-aggregation provenance problem found in
AccidentDetection-9k. However, source-specific terms require clarification:
the Accid3nD project page says CC BY-NC-SA 4.0, while the official generic
TUMTraf development kit says CC BY-NC-ND 4.0. Those licences have materially
different rules for adaptations. Until TUM confirms which terms govern the
Accid3nD archive, IRIS cannot treat derived stills, training, redistribution,
or model release as permitted. The Creative Commons licence language also does
not by itself settle privacy or other third-party rights.

### Nexar

Nexar is also first-party and has an explicit dataset-content license rather
than only a code license. The license authorizes modifying the dataset, so
reviewed local still extraction is supported. It requires attribution and
notice retention, forbids resale/profit redistribution, and restricts harmful,
misinformation, re-identification, weapon, exploitative, and unlawful uses.
The repository is public but gated, requiring login and acceptance of terms.
The license's silence about trained-model distribution is recorded as a
restriction rather than treated as permission.

### DADA, DoTA, AccidentDetection-9k, and Roboflow

DADA and DoTA remain unavailable for IRIS extraction/training until their
source-content and derived-frame permissions are explicitly clarified. DoTA's
statement about authority to share clips is valuable provenance information,
but is not substituted for a dataset-content license. AccidentDetection-9k
remains blocked by its Google-image-search chain of rights. The Roboflow record
is rejected by IRIS because its uploader-level CC BY label is not an
authoritative provenance chain for the underlying media.

### ACCIDENT benchmark

The ACCIDENT project is a stronger rights/provenance lead than web-scraped
accident collections, but it is not yet an unconditional IRIS approval. The
official paper and project page describe 2,027 real surveillance clips and
2,211 synthetic CARLA clips. The project repository requires an authenticated
Kaggle download of `picekl/accident`; no download was performed during this
qualification. The real clips are collected from heterogeneous online CCTV
sources, not recorded by the project itself.

The official supplemental policy states that only clips with upstream terms
explicitly permitting redistribution and derivative works were included, and
that each released clip retains a canonical source URL. It assigns CC BY 4.0
to annotations/metadata and Apache-2.0 to code/CARLA assets. The same policy
restricts use to research, prohibits re-identification, and provides a
take-down channel. These statements support a documented local academic
training workflow for the licensed clips, including conservative local frame
derivation, but they do not expressly grant distribution of a classifier or
TFLite model trained on the clips. IRIS therefore keeps the route
`REVIEW_REQUIRED` until the clip-level terms and model-bundling position are
confirmed. The paper's open-access status is not treated as a dataset license.

The benchmark is primarily temporal/spatial/collision-type video evaluation,
not a ready-made still-image binary classifier. It can support IRIS only after
human review of impact-time frames, exclusion of pre-impact and ambiguous
frames, and event/video-group-aware splitting. The real subset is the only
part relevant to real positive-image qualification; synthetic data remains
separate and must not be silently mixed into the real-data manifest.

### CCTV Traffic Accident Object Detection Dataset

This Hugging Face dataset traces directly to the Roboflow project named
“Accident and Non-accident label Image Dataset.” The Hugging Face card states
that it contains 1,485 unique CCTV frames and approximately 3,000 rows after
offline augmentation. The currently displayed dataset totals are 2,763 rows
and 1.01 GB. The card declares CC0-1.0 and says the original authors
designated the source Public Domain. The Roboflow record independently shows
the same two classes, 1,485 images, five dataset versions, and a Public Domain
label.

Those declarations are not sufficient to establish rights in the underlying
images. Neither page identifies the CCTV/video owners, capture source, source
URLs, contributor releases, or evidence that the publisher had authority to
dedicate every image to the public domain. No upstream provenance beyond the
Roboflow project was disclosed during this qualification. This is a material
uncertainty, not a finding that the publisher's claim is false.

The annotations are object-level: an `accident` box marks an involved region,
while a `non_accident` box marks an uninvolved visible vehicle/region. The
card explicitly allows both classes in one frame. Therefore an image with at
least one accident box can be a candidate for human image-level review, but
the box label must not be promoted automatically to an IRIS production label.
An image containing only non-accident boxes is not automatically a whole-scene
`non_accident` example.

The card describes offline letterboxing, horizontal flips, and brightness
adjustments. It reports original and expanded counts, but does not document a
stable parent-image identifier, augmentation-family field, or a mapping from
the approximately 3,000 expanded rows to the 1,485 originals. The visible
Hugging Face records also do not expose source video IDs, camera IDs, event IDs,
timestamps, or sequence/frame identifiers. Event-aware splitting therefore
cannot be established before authorized acquisition and inspection; it must
not be invented. Exact SHA-256, dHash, and any recoverable augmentation-family
grouping would be required, with all members of a group kept in one split.

The route is `REVIEW_REQUIRED`. Local academic training, frame/image-derived
manifests, trained-weight distribution, TFLite conversion, and bundling in a
noncommercial Android project all remain subject to the unresolved underlying
media rights and source-group limitations. No data was downloaded.

## Current route decision

| Route | Status | Why |
| --- | --- | --- |
| TUMTraf-Accid3nD | **REVIEW_REQUIRED** | First-party real accident capture, but the source-specific CC BY-NC-SA 4.0 statement conflicts with the generic development-kit CC BY-NC-ND 4.0 statement. Written TUM clarification is required before downloading or deriving frames. |
| ACCIDENT benchmark real subset | **REVIEW_REQUIRED** | Stronger documented clip-selection policy and canonical provenance, but Kaggle-gated acquisition, clip-level upstream terms, research/privacy restrictions, and trained-model/TFLite distribution are not fully settled for IRIS's intended release. |
| CCTV Traffic Accident Object Detection Dataset | **REVIEW_REQUIRED** | Explicit HF/Roboflow public-domain declarations exist, but authority over underlying CCTV imagery, original-vs-augmented mapping, and physical-event grouping are undocumented. |

## Required future acquisition and qualification procedure

The technically appropriate next step is to obtain a written confirmation from
TUM identifying the licence that governs the five Accid3nD archives and whether
local frame extraction/training and model distribution are allowed. Do not
download it before that confirmation. The official acquisition-plan document
records the exact archive inventory and the proposed leakage-safe workflow.

For ACCIDENT, the next step is a rights review of the authenticated Kaggle
archive metadata and each real clip's canonical upstream URL/license. No
download is approved by this document. If those records confirm derivative
frame extraction for the intended academic use, IRIS may acquire only the
real subset, preserve metadata and source URLs, and perform human-reviewed
event-group extraction. Written clarification is still required before
redistributing an IRIS-trained model or bundling a TFLite artifact for users.

For the CCTV Traffic Accident Object Detection Dataset, the current decision
is **B — acquire only for further rights/provenance inspection** if a later
task authorizes acquisition. Do not promote it to the production manifest on
the basis of the CC0/Public Domain labels alone. Any authorized inspection
must first establish whether original frames can be separated from offline
augmentations, then compute exact hashes/dHashes, inspect all available
metadata for grouping, and human-review only frames containing a visible
accident context. If those facts cannot be established, do not use the source.

After acquisition, the dataset inspector must record actual archive size,
checksums, file structure, sequence/event/camera grouping fields, readable
frames, and duplicates. The review workflow then selects only observed visible
collision/damaged-vehicle positives; it separately reviews negatives and never
uses sequence proximity alone as a label. Every original sequence/event and
multi-camera view remains in exactly one split, then the existing SHA-256 and
dHash cross-split checks are applied. No source in this document has been
inserted into `manifest.v1.csv`.

## Evidence boundaries

These records establish no classifier result, no model accuracy, no accident
finding, and no production analytical data. They document source research and
planned data controls only.
