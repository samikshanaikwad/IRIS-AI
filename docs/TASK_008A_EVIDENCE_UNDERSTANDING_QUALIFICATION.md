# TASK 008A — V0 evidence-understanding qualification

Status: `TASK 008A PARTIALLY QUALIFIED — no candidate is yet approved for Android integration`

Qualification date: 2026-09-28  
Starting implementation commit: `6e85e20` (`TASK 007: integrate real road object detection`)

This document records research only. It does not change Android production behavior, SQLite schema v5, TASK 006, or TASK 007.

## Decision summary

| Capability | Status | Decision |
|---|---|---|
| A — vehicle/road-user pixel masks | `REVIEW_REQUIRED` | Do not integrate yet |
| B — road/ground scene segmentation | `REVIEW_REQUIRED` | Strongest future candidate, exact artifact still needs qualification |
| C — visible vehicle-damage localization | `REVIEW_REQUIRED` | Technically suitable direction; CarDD access and rights remain pending |

No capability is marked `QUALIFIED`; therefore no versioned production model contract or model artifact is created by TASK 008A.

## Capability A — vehicle/road-user segmentation

### Candidates

**MobileSAM / Qualcomm AI Hub.** The official Qualcomm page describes MobileSAM as prompt-based segmentation with a TFLite deployment path. A TASK 007 box could potentially be used as a deterministic prompt to obtain an instance mask, but that would be cross-model association, not an identity guarantee. The published encoder and decoder are approximately 26.6 MB and 23.7 MB in float form, respectively. The deployment assets have a separate Qualcomm AI Hub proprietary-license document, so the exact Android artifacts and redistribution terms require compliance review. No artifact was downloaded or smoke-tested. Status: `REVIEW_REQUIRED`.

**MediaPipe Selfie Segmentation.** The official model card describes a small 256×256 human/selfie segmentation model. It does not provide vehicle or road semantics and is unsuitable for IRIS vehicle masks or scene segmentation. Status: `REJECTED` for TASK 008A.

Authoritative references: [Qualcomm MobileSAM](https://aihub.qualcomm.com/mobile/models/mobilesam), [Qualcomm compiled-asset license](https://qaihub-public-assets.s3.us-west-2.amazonaws.com/qai-hub-models/Qualcomm%20AI%20Hub%20Proprietary%20License.pdf), [MediaPipe Selfie Segmentation model card](https://storage.googleapis.com/mediapipe-assets/Model%20Card%20MediaPipe%20Selfie%20Segmentation.pdf).

### Assessment

MobileSAM is technically plausible for box-prompted masks, but it is not a road-user semantic model, its exact deployable artifact/license was not qualified, and its memory/runtime cost is materially greater than the current detector. It should not proceed to Android until an exact artifact, preprocessing/output contract, and compliance position are established.

## Capability B — basic scene segmentation

Google AI Edge's Image Segmenter API supports TFLite models with metadata and category-mask or confidence-mask outputs. Its documented DeepLabV3 example is a generic semantic segmentation route, not an IRIS-qualified artifact. The TensorFlow model/configuration documentation identifies MobileNetV2 DeepLabV3 variants for PASCAL and Cityscapes, and the TensorFlow DeepLab model zoo documents pretrained research models, but these references do not by themselves establish a redistributable Android TFLite artifact with a verified contract.

The PASCAL-style DeepLab route is not sufficient for the IRIS road/ground requirement: its known object categories do not provide a dedicated road/drivable-surface class. Cityscapes-trained segmentation is technically more relevant because Cityscapes contains urban road-scene labels, but the exact export, weight terms, model artifact hash, and dataset-use obligations still require qualification. No scene-segmentation artifact was downloaded or smoke-tested.

Status: `REVIEW_REQUIRED`, with Cityscapes-trained MobileNetV2/DeepLab as the strongest research lead. It is not a qualified model contract and must not be integrated yet.

Authoritative references: [Google AI Edge Image Segmenter](https://ai.google.dev/edge/mediapipe/api/solutions/python/mp/tasks/vision/ImageSegmenter), [TensorFlow semantic-segmentation configurations](https://www.tensorflow.org/api_docs/python/tfm/vision/configs/semantic_segmentation), [TensorFlow DeepLab model zoo](https://github.com/tensorflow/models/blob/master/research/deeplab/g3doc/model_zoo.md), [TensorFlow Datasets Cityscapes description](https://github.com/tensorflow/datasets/blob/master/docs/catalog/cityscapes.md?plain=1).

## Capability C — visible vehicle-damage localization

### CarDD technical assessment

The official CarDD project reports approximately 4,000 high-resolution car images and more than 9,000 annotated damage instances across dent, scratch, crack, glass shatter, lamp broken, and tire flat categories. This is spatially useful because the dataset supports damage localization/segmentation rather than only an image-level damage flag. It is primarily passenger-car imagery; it does not validate motorcycle, bicycle, bus, or truck damage.

The project requires a licensing form and author contact before download. The official license states that CarDD remains the property of the PIC Lab/CAS, permits scientific/statistical research subject to prior consent, requires citation, requires separate authorization for commercial use, and restricts transfer, distribution, or broadcasting to third parties. The official paper also states that images were collected from Flickr and Shutterstock and that the authors do not own those underlying copyrights; users must comply with the relevant source terms. These are material provenance and access restrictions, not merely code-license details.

Status: `REVIEW_REQUIRED` — technically suitable for later research, but access/consent and downstream rights are pending. The dataset was not downloaded and no damage inference was executed.

Authoritative references: [CarDD project](https://cardd-ustc.github.io/), [CarDD license](https://cardd-ustc.github.io/docs/CarDD_license.pdf), [CarDD paper](https://cardd-ustc.github.io/docs/CarDD.pdf).

### Damage-model review

Community CarDD-trained examples were not accepted as qualified pretrained models. Repository code licenses or a model-card license do not establish rights to the restricted CarDD-derived weights or underlying images. No authoritative, rights-cleared, mobile-ready damage-localization artifact with a verified hash and contract was found in this qualification. In particular, no model is approved for motorcycle damage; unsupported vehicle types must later produce an explicit unavailable/unsupported state rather than an inferred damage result.

## Rights and technical conclusions

- No dataset was downloaded.
- No model was trained, fine-tuned, converted, or executed for production.
- No damage, scene, or segmentation result was created.
- Existing TASK 007 EfficientDet-Lite0 and TASK 006 classifier contracts were not modified.
- A future candidate must separately document source-code license, model-weight license, training-data terms, derivative/export rights, and Android bundling rights.
- Any future damage output must be called a model-detected visible damage region/score, not a confirmed collision point or collision cause.

## Recommended next step

Do not begin Android integration from this qualification alone. The strongest technically useful route is to qualify an exact Cityscapes-trained lightweight semantic-segmentation TFLite artifact for road/ground labels, including its artifact hash and rights. In parallel, request/obtain the required CarDD consent if visible car-damage localization remains necessary. MobileSAM should remain a secondary research option because prompt-based masks and the deployment-license burden do not yet provide a clean IRIS V0 contract.

TASK 008A remains qualification-only. TASK 009 must not start until a separately approved capability and contract exist.
