# TASK 006 Pretrained Accident Model Qualification

**Research checkpoint:** 2026-09-27  
**Scope:** qualification only. No weights were downloaded, converted, trained,
evaluated, bundled, or connected to IRIS. This document creates no accident
determination capability.

## Qualification standard

TASK 006 requires a real learned model whose actual pretrained weights,
architecture, preprocessing, accident semantics, and applicable terms are
documented by an authoritative publisher. A direct model must classify one still
road image consistently with the IRIS contract:

- `accident`: the still visibly supports a collision, crash, rollover, or
  clearly accident-damaged road-vehicle context; and
- `non_accident`: the still visibly supports a normal road/traffic scene with
  no accident.

Video anticipation, collision-risk, near-miss, and anomaly models do not meet
that still-image decision. Code terms, a hosting-site license label, model-file
availability, the weights license, and training-media provenance are separate
questions. The states below are IRIS engineering controls, not legal advice.

All sources were accessed on 2026-09-27. Publisher metrics are not IRIS
evaluation results and are not used as IRIS performance claims.

## Qualification table

| Candidate | Authority and real artifact | Semantics / technical suitability | Rights and provenance review | IRIS status |
| --- | --- | --- | --- | --- |
| **BADAS-Open** | [Nexar AI model record](https://huggingface.co/nexar-ai/BADAS-Open), [Nexar source repository](https://github.com/getnexar/BADAS-Open), Goldshmidt, Scott, Niccolini, Zhu, Moura, and Zvitia, [paper](https://arxiv.org/abs/2510.14876). Actual `model.safetensors` is advertised but gated: login, contact sharing, and condition acceptance are required before access. | PyTorch V-JEPA2 ViT-L encoder, attentive aggregation, and 3-layer MLP; 16 frames at 256x256; output is ego-centric collision risk. It predicts future threat from video, explicitly learns near misses, and is not a visible-accident still classifier. No official LiteRT artifact, size, or conversion path was found. | The model page and source repo identify Apache-2.0 for their work and state attribution/modification/redistribution claims, but actual weights are gated. Training is stated as 1,500 Nexar videos: 750 collision/**near-miss** and 750 normal. The record does not establish unrestricted rights in the underlying training videos. | **REJECTED** |
| **Crashly** | [Hugging Face model record](https://huggingface.co/namelessai/Crashly), uploader `namelessai`. An 8.87 MB `Crashly.tflite` is listed and tagged MobileNetV2, LiteRT, image classification, and accident detection. | The card describes traffic-camera crash detection and RGB float preprocessing scaled to [-1,1], but gives no authoritative input size, output-label mapping, architecture configuration, evaluation protocol, or label policy. It is technically a single-image LiteRT artifact. | The host displays Apache-2.0, but no authoritative project, identifiable author affiliation, paper, separate weights license, training dataset, source-media provenance, or training record was found. A host label cannot prove that the uploader can license the weights or training media. Modification/conversion and redistribution rights are unproven. | **REJECTED** |
| **Car Crash Dataset (CCD) / associated accident-anticipation research** | [Official Cogito2012 dataset repository](https://github.com/Cogito2012/CarCrashDataset), Bao, Yu, and Kong, *Uncertainty-based Traffic Accident Anticipation with Spatio-Temporal Relational Learning*. The repository exposes videos, VGG-16 features, annotations, and splits, not a pretrained end-to-end accident classifier weight file. | It has 1,500 crash clips and 3,000 normal clips, each 50 frames. This is temporal anticipation data, not a deployed one-still model. | No model-weights license, classifier conversion permission, or classifier redistribution permission was found. Source videos are described as YouTube crash clips and BDD100K normal clips, which does not resolve a rights chain for an IRIS-derived classifier. | **REJECTED** |
| **MobileNetV3Small ImageNet checkpoint (fallback backbone, not an accident model)** | [Official TensorFlow/Keras API](https://www.tensorflow.org/api_docs/python/tf/keras/applications/MobileNetV3Small) and [TensorFlow Model Garden](https://github.com/tensorflow/models). Official Keras exposes `weights='imagenet'`; standard 1.0/224 has 2.9 M parameters and 66 M MACs. | A single-image CNN at 224x224 RGB. Keras documents preprocessing inside the model ([0,255]) or outside it ([-1,1]). Its output is ImageNet classes, not accident/non-accident, so real later fine-tuning and evaluation would be required. TensorFlow documents normal LiteRT conversion and post-training quantization workflows. | TensorFlow source code is Apache-2.0. The reviewed official pages identify ImageNet pretraining but do not supply a separate explicit checkpoint license or resolve underlying ImageNet image rights. IRIS does not infer checkpoint modification or redistribution permission from the code license. | **REVIEW_REQUIRED** |

## Findings

### BADAS-Open

BADAS is an identifiable, real pretrained release, but its authoritative model
card says it is a 16-frame dashcam collision-prediction model. It learns from
both collision and near-miss events and focuses on threats to the ego vehicle.
That is incompatible with IRIS's one-still visible-accident question: a
pre-impact frame can receive a risk score without visibly proving a collision,
while an aftermath image is not necessarily the advertised task. The semantic
mismatch independently rejects direct use, regardless of gated access or
conversion difficulty.

Nexar reports Apache-2.0 and attribution requirements for its release, while
the current hosted weights are gated. IRIS did not accept the conditions or
download them. Any benchmark numbers on the model card remain Nexar's claims,
not IRIS results.

### Crashly

Crashly is a technically convenient one-image LiteRT file, but convenience is
not qualification. Its page has no traceable training-data provenance, model
author/project, reproducible training record, separate weights terms, or
documented IRIS-compatible semantics. It is rejected rather than adopted as an
untraceable shortcut.

### CCD

CCD is an authoritative research data record, not a qualifying pretrained-model
release. It supplies temporal video/features and labels, not a published
end-to-end classifier weight artifact. Its temporal labels also cannot be
converted into IRIS visible-accident still labels without real human review.

### MobileNetV3Small fallback

MobileNetV3Small is the strongest engineering fallback, not a direct solution.
It is small, one-image, and compatible with TensorFlow's standard LiteRT
workflow, but it recognizes ImageNet categories. Before a separately authorized
training task, IRIS must obtain a rights-cleared, semantically reviewed,
leakage-safe still dataset and complete a checkpoint/weight compliance review.
No model conversion, quantization, training, or evaluation was performed here.

## Decision

**No direct pretrained accident classifier is `QUALIFIED` or
`QUALIFIED_WITH_RESTRICTIONS` for IRIS TASK 006.** An existing direct model is
not preferable to a future IRIS training/evaluation effort using a
rights-cleared, group-safe still-image dataset.

The strongest technically legitimate path is to first resolve the dataset
blockers in [ACCIDENT_DATASET_QUALIFICATION.md](ACCIDENT_DATASET_QUALIFICATION.md),
then use a separately approved small backbone such as MobileNetV3Small only if
checkpoint rights are confirmed and real training/evaluation can proceed. Do
not download or integrate it now.

BADAS access requires user login, contact sharing, and acceptance of the
publisher's gate. Because BADAS is rejected for IRIS semantics, this is not a
recommended next action.

## Boundaries

No model was added to `app/`; no Android dependency, SQLite schema, production
manifest, or production code changed. This document contains no classifier,
training data, benchmark, inference result, confidence value, or accident
conclusion.
