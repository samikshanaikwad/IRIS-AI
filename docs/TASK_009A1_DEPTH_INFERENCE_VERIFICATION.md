# TASK 009A.1 — Depth Anything V2 Small source inference verification

Decision: `TASK 009A.1 PARTIALLY QUALIFIED — SOURCE DEPTH MODEL VERIFIED, MOBILE DEPLOYMENT BLOCKED`  
Starting commit: `4f46fc0`  
Official source commit: `a561b849ebae10a6f5ef49e26c83cbbcd36c71bf`

## Environment

- Isolated environment: `C:\Users\DELL\Desktop\IRIS\.local-tools\depth-venv`
- Python: 3.12.10
- PyTorch: 2.14.0+cpu
- torchvision: 0.29.0
- Device: CPU
- Health check: `torch.tensor([1., 2.]).sum()` returned `3.0`
- The prior TASK 006 environment was not modified.

## Exact source artifact

- Model: `Depth-Anything-V2-Small`
- Variant: ViT-S/DPT relative-depth model
- Parameters: 24.8M
- Filename: `depth_anything_v2_vits.pth`
- Source: official project-linked Hugging Face checkpoint
- Size: 99,218,434 bytes
- SHA-256: `715FADE13BE8F229F8A70CC02066F656F2423A59EFFD0579197BBF57860E1378`
- Retrieval: 2026-09-28

The project documents the Small checkpoint as Apache-2.0. This is recorded separately from the provenance and terms of the data used to train the model. The checkpoint is retained only in ignored local qualification tooling and is not committed.

## Source inference contract

- Input source: BGR OpenCV image converted to RGB
- Numeric conversion: float32 RGB values divided by 255
- Resize: aspect-preserving lower-bound resize around input size 518, preserving a multiple of 14; no crop
- Normalization: mean `[0.485, 0.456, 0.406]`, standard deviation `[0.229, 0.224, 0.225]`
- Tensor layout: `1×3×H×W` float32 after `PrepareForNet`
- Output: float32 `H×W` map, bilinearly resized back to the original image dimensions
- Output semantics: affine-invariant/relative depth-like model output, not meters
- Output direction: larger values represent nearer/foreground structure; this is consistent with the official ReLU-constrained depth head and the real-image visual sanity check below

The source implementation does not establish forensic distance, camera scale, ground-plane geometry, or 3D coordinates.

## Real-image execution

Three real locally stored AccidentDetection-9k review images were used temporarily; no private phone evidence was copied or modified and no images were committed. The images were 640×640 JPEGs. All outputs were finite, float32, 640×640, and had nonzero variation:

| Image | min | max | mean | standard deviation | CPU time |
|---|---:|---:|---:|---:|---:|
| `000001_d576d2070515.jpg` | 0.0000 | 5.6805 | 2.4067 | 1.7085 | 1.273 s |
| `000002_ced60fdede69.jpg` | 0.0000 | 6.8857 | 2.2683 | 1.9863 | 1.624 s |
| `000003_91ef787a3a48.jpg` | 0.0000 | 9.2563 | 2.2491 | 2.2911 | 1.542 s |

These are development-machine CPU timings, not Realme timings. Temporary colorized visualizations were generated from the raw model outputs for inspection and remain ignored. The first image showed plausible foreground emphasis on the nearby wreckage and lower scene, with more distant people/structures represented farther away. This is a sanity check, not an accuracy benchmark.

## Mobile qualification status

No official TFLite/LiteRT artifact was identified. No conversion was attempted in this bounded repair because the official model is a ViT/DPT PyTorch checkpoint and an Android deployable export would require a separate export, operator-compatibility, and source-vs-mobile parity investigation. No ONNX artifact was produced. Therefore mobile execution, converted-artifact SHA, and parity are unverified.

TASK 007 box sampling remains a future deterministic design issue: use robust multi-pixel sampling inside a real detector box rather than its center pixel. Without TASK 008 masks, detector boxes may include background, so any later object-depth estimate must carry that uncertainty.

No depth contract was created under `datasets/manifests/depth/` because full qualification requires a verified deployable artifact and parity.
