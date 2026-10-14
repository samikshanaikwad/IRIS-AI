# TASK012 Phase A2 — real vehicle segmentation qualification

## Decision: QUALIFIED for car and motorcycle box-prompt masks

The upstream Apache-2.0 MobileSAM ViT-T encoder and decoder produced genuine,
original-image-aligned instance masks on a physical realme RMX3780 (Android 15,
arm64-v8a). Qualification is deliberately limited to `car` and `motorcycle`,
the classes represented by successful rights-cleared public evaluations.
`bicycle`, `bus`, and `truck` remain unqualified.

This decision qualifies an isolated debug-only mask generator, not production
segmentation, damage classification, or the 3D renderer. Production remains
fail-closed and unchanged. A mask identifies prompt-conditioned visible pixels;
it does not establish hidden geometry, damage semantics, vehicle identity, or
metric dimensions.

## Governed model identity

- Upstream source: [ChaoningZhang/MobileSAM](https://github.com/ChaoningZhang/MobileSAM),
  commit `f706ad9c4eb7f219c00d9050e46328518ffb65d2`.
- Upstream checkpoint SHA-256:
  `6dbb90523a35330fedd7f1d3dfc66f995213d81b29a5ca8108dbcdd4e37d6c2f`.
- Encoder ONNX SHA-256:
  `f55b0f6c6949d4737ba06ddf14b99b35ae7c26c782f9865078e34b0a0f45df49`.
- Box-prompt decoder ONNX SHA-256:
  `4a3d6ee977ce5ad077e1ab980db5f1bffb96758c4029a2abccd0d08634a8bf63`.
- Upstream Apache-2.0 license-file SHA-256:
  `c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4`.
- Detector prompt source: the bundled TASK007 EfficientDet-Lite0 artifact,
  SHA-256 `2e04c53bfeac0ac2a30c057c7e2a777594ce39baaac35a92f74fb1e8c4fc4e0b`.
- Coordinate mapping: `iris-image-coordinate-v2`.

The pinned source tree and checkpoint are Apache-2.0. Product legal review and
retention of upstream notices are still required before redistribution in a
release build. The ONNX files remain ignored local qualification artifacts and
are included only in debug builds when explicitly present.

## Genuine public evaluation set

Seven images were downloaded over normally validated HTTPS from Wikimedia
Commons and accepted only after SHA-256 verification. Their source pages,
authors, licenses, download URLs, and exact image hashes are governed by
`ml/segmentation/qualification/public_vehicle_evaluation.v1.json`.

No public image was imported into a case. No user database or missing private
motorcycle evidence was used or recreated. The debug runner copied each
verified public image only to app-private cache.

## Physical-device results

All prompts below came from genuine TASK007 output. MobileSAM was not invoked
when the required target-class prompt was absent.

| Evaluation | Result | Prompts | Detector ms | Encoder ms | Decoder ms | Total ms | Peak PSS kB |
|---|---:|---:|---:|---:|---:|---:|---:|
| motorcycle-clean | success | 1 | 132 | 2818.8 | 239.7 | 8115.9 | 818256 |
| motorcycle-damaged | success | 1 | 60 | 2828.5 | 202.3 | 7307.3 | 1149500 |
| motorcycle-partial-edge | success | 1 | 58 | 2665.3 | 256.5 | 8505.0 | 1191252 |
| motorcycles-multiple | success | 3 | 80 | 2694.0 | 578.6 | 12581.6 | 1223628 |
| car-full | success | 2 | 79 | 2662.8 | 382.5 | 8302.9 | 1212564 |
| car-partial-edge | **no reliable mask** | 0 | 59 | — | — | — | — |
| cars-dense-traffic | success | 11 | 58 | 3286.9 | 2127.6 | 31551.3 | 1241246 |

Across the six successful images, mean detector time was 77.8 ms, mean encoder
time 2826.1 ms, mean summed decoder time 631.2 ms, and mean end-to-end runner
time 12727.4 ms. Maximum end-to-end time was 31551.3 ms for eleven dense-traffic
instances. Peak sampled process PSS was 1,241,246 kB (1,212.2 MiB).

The memory value is sampled Android process **PSS**, not RSS and not an
incremental model-only allocation. Sessions remained resident during the
sequential debug run, so production integration must define explicit lifecycle,
batching, cancellation, and low-memory behavior.

The fail-closed gate's documented offline-analysis thresholds are at most
35,000 ms per evaluated image and at most 1.5 GiB sampled process PSS. These are
qualification thresholds for a deferred evidence-analysis operation, not an
interactive frame-time target.

## Visual overlay review

- The clean, damaged, and partly cropped motorcycles followed their visible
  silhouettes in the original raster. The damaged example retained its
  irregular fallen outline rather than becoming a detector rectangle.
- Three adjacent motorcycles produced three separately aligned masks.
- The full-car image produced separate masks for the foreground car and one
  visible background car.
- Dense traffic produced eleven separately aligned car masks across occlusion
  and scale variation.
- The cropped yellow car remains an explicit failure: TASK007 labelled it
  `bus`, so there was no governed `car` prompt. No manual box, substitute class,
  or fabricated mask was used.

These are documented visual inspections, not ground-truth pixel IoU scores.
MobileSAM's predicted quality and mask/box overlap are diagnostics, not forensic
accuracy measurements.

Exact image, model, mask, overlay, latency, and memory records are retained in
`ml/segmentation/qualification/rmx3780_public_run_summary.v1.json`. The complete
hash-verified package is local and ignored at:

`.local-tools/segmentation-qualification/qualification-package-rmx3780`

Its `run.json` SHA-256 is
`def065ee39a39a4a48d6e76047a1424ffc130683d01388cd0b8b0c8cf6605bce`.
Generated overlays are in that package's `overlays/` directory and the captured
device-run directory. Licensing and share-alike obligations remain attached to
source images and derivative overlays; the artifacts are not release assets.

## Fail-closed evidence gate

`validate_qualification_run.py` now requires:

- a physical Android device identity;
- exact model, public-image, mask, and overlay hashes;
- cleared non-synthetic image provenance;
- `iris-image-coordinate-v2`;
- genuine TASK007 prompt provenance and the exact detector hash;
- one recorded mask per prompt;
- accepted documented visual review for every successful image;
- per-image detector, encoder, decoder, total-latency, and sampled-PSS values;
- exact agreement between successful observed classes and claimed classes.

The validator rejects synthetic evidence, manual/substitute prompts, missing
mask artifacts, an RSS label substituted for PSS, failed evaluations carrying
mask files, and performance beyond the documented thresholds. The assembled
Realme package passes this gate.

## Candidate comparison and limits

| Candidate | Outcome |
|---|---|
| MobileSAM ViT-T, TASK007 box prompt | **QUALIFIED** for observed `car` and `motorcycle` masks only. |
| MediaPipe bundled image segmenters | **REJECTED**: documented category/semantic outputs do not satisfy per-vehicle instances. |
| TorchVision Mask R-CNN ResNet50-FPN | **REJECTED** for this device path: checkpoint/runtime cost and no qualified Android deployment. |
| Ultralytics segmentation | **BLOCKED**: AGPL/commercial redistribution authority is not established. |

MobileSAM is class-agnostic. Vehicle class provenance remains TASK007's, and a
TASK007 miss or misclassification can prevent segmentation, as the cropped-car
failure demonstrates. No claim is made for bicycle, bus, or truck.

## Next milestone (not started)

Phase A3 should design a production evidence-segmentation record and lifecycle
for the qualified classes, preserve source-image color only inside observed
mask pixels, and fuse those pixels with current relative XYZ/UV geometry into
an explicitly partial, non-metric surface. It must retain a labelled category
proxy when segmentation is unavailable, must not infer unseen geometry or
damage, and must add device memory controls before enabling production use.
