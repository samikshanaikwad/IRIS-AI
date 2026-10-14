# TASK012 Phase A2 — vehicle segmentation qualification status

## Decision: BLOCKED (candidate runner compiled; no model qualification claim)

No model has been qualified. The pinned MobileSAM checkpoint was exported to
ONNX and an isolated debug-only Android runner compiled, but the existing
Realme case was not accessed or modified: the connected phone does not have the
repository's application ID (`com.iris.incidentreconstruction`) installed.
The app's existing evidence therefore could not be passed through IRIS's normal
evidence repository to the runner. No model inference, mask, overlay, latency,
or device-memory result was produced. Do not infer success from the ONNX export
or APK build.

## Candidate comparison

| Candidate | Actual capability and classes | License/deployment finding | Decision |
|---|---|---|---|
| MobileSAM ViT-T, box prompt | Class-agnostic prompt mask. It has no learned vehicle labels; a current eligible TASK007 box is only a prompt. Supported IRIS classes remain unqualified until genuine device results are evaluated per class. | Pinned upstream source tree carries Apache-2.0. A local encoder and official prompt decoder were exported to ONNX for the existing Android ONNX Runtime. Checkpoint redistribution/product legal review remains required. | **BLOCKED** pending real RMX3780 inference and a sufficiently broad, rights-cleared evaluation. |
| MediaPipe Image Segmenter candidates | Documented category/semantic masks, not separate instances for car, motorcycle, bus, truck and bicycle. | Android API is available; exact model files and terms vary, but the documented category contract is insufficient. | **REJECTED** for this instance-mask requirement. |
| TorchVision Mask R-CNN ResNet50-FPN COCO | Class-labelled COCO instances include the target vehicle labels. | BSD code, but the official checkpoint is about 170 MB and no qualified offline Android path/performance exists for this device. COCO image rights are independent. | **REJECTED** as the practical RMX3780 candidate. |

Ultralytics segmentation is not shortlisted: its AGPL/commercial licensing path
has not been cleared for this application. No Ultralytics artifact was obtained.

## Pinned local MobileSAM artifacts

- Source: [ChaoningZhang/MobileSAM](https://github.com/ChaoningZhang/MobileSAM),
  commit `f706ad9c4eb7f219c00d9050e46328518ffb65d2`.
- Checkpoint: upstream `weights/mobile_sam.pt`, SHA-256
  `6dbb90523a35330fedd7f1d3dfc66f995213d81b29a5ca8108dbcdd4e37d6c2f`.
- Encoder ONNX (opset 17), SHA-256
  `f55b0f6c6949d4737ba06ddf14b99b35ae7c26c782f9865078e34b0a0f45df49`.
- Box-prompt decoder ONNX (opset 17), SHA-256
  `4a3d6ee977ce5ad077e1ab980db5f1bffb96758c4029a2abccd0d08634a8bf63`.
- Model input uses the upstream 1024-long-side RGB resize, mean/std
  normalization, and bottom/right zero padding. The prompt is the two
  transformed corners of a real TASK007 detection box (labels 2 and 3).
  Decoder masks are mapped to the EXIF-oriented original raster using
  `iris-image-coordinate-v2`.
- Export utility: `ml/segmentation/qualification/export_mobilesam_onnx.py`.
  The ONNX files and source checkpoint remain in ignored `.local-tools`; they
  are not committed or included in release assets. The debug APK obtains model
  assets from that local export directory and includes the upstream license.

MobileSAM is class-agnostic. It does not label an instance, establish vehicle
identity, or identify damage. A mask only means the prompt-conditioned model
selected those pixels; predicted quality and mask/box overlap are not
ground-truth accuracy measurements.

## Isolated runner and data boundary

The qualification panel appears only in Flutter debug mode. Android registers
the method channel only in a debuggable app. The runner accepts current,
persisted eligible TASK007 boxes with v2 coordinate metadata; it rejects
non-private file paths and does not rerun TASK007. It invokes the ONNX encoder
once and decoder per eligible instance. It writes a single composited visual
overlay to app-private cache, replacing the prior qualification overlay. It
does not write masks or overlays into SQLite, evidence storage, reconstruction
geometry, or the production renderer. The overlay colors are solely diagnostic.

The connected device read-only facts were RMX3780/RMX3780IN, Android 15,
arm64-v8a, MediaTek MT6835, and approximately 7.8 GB reported physical RAM.
`pm path com.iris.incidentreconstruction` returned no installed package. The
device exposed `com.aistudio.aperture3d.forensics`, but its relationship to this
IRIS repository was not established. To avoid a new empty app instance being
mistaken for the existing case or overwriting another app, no install, launch,
evidence access, or inference was attempted. No image, database, or app-private
data was exported.

## Required next step

Confirm whether `com.aistudio.aperture3d.forensics` is the installed IRIS case
store, or identify the correct repository app package. Resolve that identity
before installing/updating anything; do not export the image or database. Once
the app identity is resolved, open the same evidence item's
detail screen in the debug build and tap **Run real on-device mask
qualification**. Inspect the on-device overlay and record measured latency and
sampled PSS. Then evaluate rights-cleared, independently sourced intact,
damaged, cluttered/occluded and multiple-instance images with ground-truth
masks. Do not claim vehicle-class support until genuine results establish it.

Because only the user's current damaged-evidence image was authorized for
on-device-only use, it was not copied to the workstation. The package mismatch
prevented even that local run. There are no mask-overlay artifacts or Android
latency/memory measurements from this phase.
