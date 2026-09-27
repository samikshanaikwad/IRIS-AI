# TASK 006 Accident-Positive Dataset Qualification

**Research checkpoint:** 2026-09-27
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
2026-09-27. No rights are inferred where the authoritative source is silent.

## Qualification table

| Candidate | Authoritative source and publisher | Media / scale / grouping | Content rights and downstream status | Still-image suitability | IRIS status |
| --- | --- | --- | --- | --- | --- |
| **TUM Traffic Accid3nD (TUMTraf-Accid3nD)** | [Official TUM project](https://accident-dataset.github.io/), Zimmer et al.; [paper](https://arxiv.org/abs/2503.12095) | First-party roadside camera/LiDAR collection at the A9 Digital Test Field, Munich. Project reports 111,945 labeled frames, four cameras plus LiDAR at 25 Hz, 2,634,233 labels, and OpenLABEL. The site does not state an archive byte size. Sequences/events and multi-camera views must be indivisible groups after acquisition. | The project explicitly states **CC BY-NC-SA 4.0** for the dataset. It permits sharing and adaptation with attribution, non-commercial use, and ShareAlike. Local derived stills are permitted under those conditions. Source/derived-media redistribution is restricted by NC/SA obligations. The project does not separately state trained-model distribution terms; obtain licence-compliance review before distributing such a model. The development kit's MIT license applies to code only. | Strong positive provenance: project-recorded real collisions, rollovers, and fires. Frames need human selection because pre-event/transition frames do not establish a visible accident; possible negatives require separate review. | **QUALIFIED_WITH_RESTRICTIONS** |
| **Nexar Collision Prediction Dataset** | [Official Nexar Hugging Face record](https://huggingface.co/datasets/nexar-ai/nexar_collision_prediction), Nexar Inc.; [dataset paper](https://arxiv.org/abs/2503.03848); [dataset license](https://huggingface.co/datasets/nexar-ai/nexar_collision_prediction/blob/main/LICENSE) | Nexar dashcam video: 1,500 1280x720, 30 fps videos, typically about 40 seconds; official repository reports 31.4 GB. Half are event-positive and half regular driving. One video ID must be one split group; frames may not be randomly split. | Copyright 2025 Nexar Inc. The Nexar Open Data License explicitly permits use, copying, modification, and distribution with required attribution/notices; it prohibits resale/profit redistribution and imposes ethical/privacy restrictions. Access is gated: an account must agree to share contact information and accept the terms. The license does not expressly address trained-model distribution, so that remains a release review item. | Useful positives only after visual selection: the source treats actual collisions **and near-misses/imminent collisions** as positive. IRIS excludes the latter from `accident`. Regular-driving videos are negative candidates only after individual-frame review. | **QUALIFIED_WITH_RESTRICTIONS** |
| **DADA-2000 / DADA** | [Official author repository](https://github.com/JWFangit/LOTVS-DADA); Fang et al., [paper](https://arxiv.org/abs/1912.03077) | Crowdsourced accident-scenario video. The paper reports 2,000 clips, about 658,476 frames, 54 accident types, temporal accident windows, and spatial crash-object annotations. The author repository advertises roughly 53 GB compressed training/test data and roughly 116 GB compressed full data through Drive/Baidu links. Clip ID is an appropriate future group. | The author repository invites use/share and asks for paper citation, but it has no published dataset-content license and gives no explicit permission for training, derived frames, source-media redistribution, or trained-model distribution. No download was attempted. | Temporal accident context is not a still label. Accident-visible windows could be reproducibly proposed from annotations, then reviewed. Pre-impact and precursor frames cannot automatically become either class. | **REVIEW_REQUIRED** |
| **DoTA** | [Official repository](https://github.com/MoonBlvd/Detection-of-Traffic-Anomaly), inspected at commit `f8f603b8c06a946bc314752947ed480a4f33f82a`; [paper](https://arxiv.org/abs/2004.03044) | YouTube-derived traffic anomaly clips; official metadata has 4,677 clips and describes approximately 55 GB of extracted frames. Original source-video grouping is recoverable and must replace the publisher clip split. | The repository's MIT text is a **code** license. The README says the authors obtained authority from original channel authors to share clips, but current official README/repository/issue inspection supplied no separate content license or explicit local derived-frame/training/model-distribution terms. No new clarification was found; an unanswered or closed issue is not permission. | The anomaly start can precede visible impact, so frames require a reviewed collision-visible window. Some anomaly types are not collisions. | **REVIEW_REQUIRED** |
| **AccidentDetection-9k v2** | [Official Mendeley record](https://data.mendeley.com/datasets/4x5my8gbcs/2), DOI `10.17632/4x5my8gbcs.2` | Locally acquired/inspected: 9,002 readable images; 8,853 technical `Accident` annotation candidates. Extensive exact and perceptual duplicates cross its publisher splits. | The record declares CC BY 4.0, but the publisher says imagery was collected through Google image search and its README retains rights with original creators/rightsholders. The record does not independently establish rights for each web image. | Bounding-box annotation does not replace IRIS visible-accident review; technical candidates remain pending. | **REVIEW_REQUIRED** |
| **Dataset Klasifikasi Kecelakaan** (Roboflow) | [Roboflow Universe record](https://universe.roboflow.com/asraf/dataset-klasifikasi-kecelakaan), uploader shown as Asraf | Record exposes accident/no-accident classification, 6,279 images and two versions. No data was downloaded; no original non-Roboflow publisher was located. | The page displays CC BY 4.0, but provides no documented ownership, original image sources, chain of rights, or evidence that the uploader originated the media. A host-level label alone is insufficient for IRIS. | Its binary labels and duplicate/leakage properties cannot be trusted without source provenance and direct inspection. | **REJECTED** |

## Rights and provenance findings

### TUMTraf-Accid3nD

This is the strongest currently located first-party academic positive source.
The official project says its own roadside sensors recorded real highway
accidents, which resolves the web-aggregation provenance problem found in
AccidentDetection-9k. Its stated CC BY-NC-SA 4.0 data license allows the
planned non-commercial academic use and local frame extraction, provided the
attribution, change-marking, and ShareAlike obligations are met. The Creative
Commons license does not eliminate possible privacy or other third-party
rights, and the project does not separately state rights for a released trained
model. IRIS must preserve the license notice and obtain a release-specific
review before distributing any model or dataset-derived material.

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

## Required future acquisition and qualification procedure

The technically appropriate next acquisition is **TUMTraf-Accid3nD**, using
only its official project data link under CC BY-NC-SA 4.0. It should be
acquired only when the next approved task includes storage planning and the
licence-compliance workflow. Do not automatically acquire it from this
qualification checkpoint.

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
