# TASK012 Phase A1 — image coordinates and segmentation qualification

## Outcome

The image-coordinate portion is implemented as
`iris-image-coordinate-v2`. The segmentation decision is **BLOCKED**: no
candidate currently has all of an authorized exact artifact, proven vehicle
instance behaviour, a governed Android execution path, genuine evaluation-mask
results, and measured RMX3780 latency/memory. No segmentation model or generated
mask has been added to production.

## Coordinate contract

The managed original remains byte-for-byte unchanged. Coordinates use continuous
pixel edges: `(0, 0)` is the top-left image edge and `(width, height)` is the
bottom-right edge. Pixel centres are represented with `+0.5` before normalization.

Spaces and transformations:

1. `RAW_ORIGINAL`: encoded raster dimensions before EXIF presentation.
2. `ORIENTED_ORIGINAL`: all EXIF values 1–8 applied, including horizontal and
   vertical mirrors, transpose and transverse.
3. Model canvas: an explicit placement records canvas dimensions, resized
   dimensions and signed offsets. `containLetterbox` and `coverCrop` are both
   represented. Detector floor rounding and depth nearest rounding remain exact.
4. A model-space point maps back through the inverse placement and inverse EXIF
   affine transform. Letterbox padding and points outside the managed original
   are rejected rather than clamped.
5. Mapping between detector, depth and future segmentation canvases goes through
   the same raw original. It never assumes equal normalized coordinates when
   input size, padding or rounding differs.

The native classifier, detector and depth runtimes now share one EXIF orientation
implementation. Detector and depth return exact coordinate metadata. Schema v17
stores that metadata for new analyses in nullable columns. Existing analyses keep
their legacy values and remain readable; a null coordinate contract is not
silently described as v2. No existing depth, detections or alignments are
rewritten or re-run by the migration.

The Flutter display uses the platform image decoder, while analytical mapping is
defined only by the persisted v2 metadata. A future mask overlay must use the
analytical transform and may not infer alignment from widget layout.

## Existing path findings

Before v2, classifier supported all mirrored EXIF orientations, but detector and
depth handled rotations only. Detector preprocessing uses 320×320 contain/floor;
depth uses 518×518 contain/nearest. Detection boxes are normalized detector-canvas
coordinates. TASK009C UVs are normalized depth-canvas sample centres. Directly
equating these spaces is only approximate; v2 supplies the exact conversion.

TASK009C stays relative, normalized and uncalibrated. The coordinate contract
does not make monocular depth metric and does not alter the TASK012 map frame.

## Candidate review

### MobileSAM ViT-T, box prompted — BLOCKED

Official source: <https://github.com/ChaoningZhang/MobileSAM>. The repository and
model are declared Apache-2.0 and describe class-agnostic point/box-prompted masks.
A genuine TASK007 box could prompt one object at a time while TASK007 retains the
class provenance. MobileSAM itself does not establish a class label or identity.

The official project documents PyTorch and an ONNX prompt-encoder/mask-decoder
export, but IRIS does not have a governed pair of Android encoder/decoder artifacts.
Qualcomm AI Hub reports float encoder/decoder sizes of approximately 26.6 MB and
23.7 MB and currently labels the model unsupported on mobile chipsets. No exact
artifact was downloaded, so no model SHA-256 is reported. No RMX3780 latency,
peak RSS, damaged-object quality or multi-instance quality was measured.

### MediaPipe bundled Image Segmenter models — REJECTED

Official source:
<https://developers.google.com/edge/mediapipe/solutions/vision/image_segmenter>.
The Android API supports category/confidence masks, but its documented bundled
models are person-part or generic semantic segmentation. They do not supply the
required per-vehicle instances and cannot separate two same-class vehicles merely
because the API returns a mask. Semantic segmentation is not substituted for the
required instance contract.

### TorchVision Mask R-CNN ResNet50-FPN COCO — REJECTED

Official source:
<https://docs.pytorch.org/vision/master/_modules/torchvision/models/detection/mask_rcnn.html>.
It produces COCO instance masks for the required road-user categories, but the
official V1 checkpoint is approximately 169.84 MB before runtime and activation
memory. IRIS has no governed Android artifact or demonstrated RMX3780 execution
path. TorchVision code is BSD-3-Clause; image/dataset rights remain independent.

### Ultralytics instance segmentation — BLOCKED

Official source: <https://docs.ultralytics.com/>. Ultralytics documents AGPL-3.0
and a separate Enterprise licence for proprietary production integration. IRIS
has no Enterprise licence on record and cannot assume that exporting weights
removes the licensing obligations. No artifact was downloaded or run.

## Qualification gate

`ml/segmentation/qualification/candidates.v1.json` is the reviewed inventory.
`validate_qualification_run.py` is a development-only, fail-closed evidence gate.
It does not manufacture or infer masks. A model-specific runner must first produce
a run record containing:

- exact local artifact paths and SHA-256 values;
- genuine, rights-cleared image paths, hashes and provenance;
- physical Android device identity;
- current coordinate-contract version;
- per-image success/unsupported/failure status;
- hashed mask and overlay artifacts for each claimed success;
- measured inference samples and peak RSS;
- supported classes equal to, and only to, successful real results.

The gate rejects synthetic images as model-quality evidence. Synthetic fixtures
remain allowed only in its own unit test and the coordinate tests. Because no
candidate cleared the artifact/runtime gate, a model-specific runner and real
overlays were not created; presenting a hand-generated overlay would violate the
task's evidence rule.

## Required next step

Obtain an exact, authorized MobileSAM encoder+decoder artifact pair or another
candidate with equivalent instance behaviour. Record source, licence, version and
hashes before integration. Then implement a debug-only ONNX Runtime runner using
TASK007 boxes as prompts, run it against a rights-cleared damaged/intact,
occluded/cluttered, multi-object evaluation set, and measure it on RMX3780. Only a
passing run may introduce a production segmentation artifact. The production 3D
renderer remains unchanged in Phase A1.
