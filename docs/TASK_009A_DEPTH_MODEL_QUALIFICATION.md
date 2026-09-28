# TASK 009A — V0 monocular depth qualification

Decision: `TASK 009A BLOCKED — V0 depth model not qualified`  
Qualification date: 2026-09-28  
Starting commit: `7edcd76`

This was a bounded investigation of the official Depth Anything V2 Small relative and outdoor metric variants. No Android, SQLite, TASK 006, TASK 007, or TASK 008 behavior was changed.

## Candidate identity

The official [Depth Anything V2 repository](https://github.com/DepthAnything/Depth-Anything-V2) identifies:

- Relative model: `Depth-Anything-V2-Small`, ViT-S/DPT, 24.8M parameters.
- Outdoor metric model: `Depth-Anything-V2-Metric-VKITTI-Small`, ViT-S with the metric DPT head, 24.8M parameters.
- Official metric checkpoint filename: `depth_anything_v2_metric_vkitti_vits.pth`.
- Official checkpoint source: the Hugging Face download linked by the project’s [metric-depth README](https://github.com/DepthAnything/Depth-Anything-V2/blob/main/metric_depth/README.md).
- Outdoor metric training/fine-tuning source: Virtual KITTI 2, as stated by the project.

The official README documents the ordinary Small output as a raw `HxW` relative-depth map. It documents the outdoor metric model as an `HxW` depth map in meters, using `max_depth=80` for the outdoor model. These semantics must not be conflated: the relative model is not meters, and the metric model’s learned scale is not forensic ground truth.

## Qualification gate

| Requirement | Result |
|---|---|
| Exact model identified | Pass |
| Official source identified | Pass |
| Actual checkpoint obtained and hashed | Fail |
| Rights/status independently recorded | Partial |
| Official preprocessing established | Partial |
| Output semantics established | Pass from project documentation |
| Real inference executed | Fail |
| Multiple real-image sanity tests | Fail |
| Depth direction verified by execution | Fail |
| Mobile deployment route demonstrated | Fail |
| Conversion parity | Not attempted |

The official project repository states that the Small model is Apache-2.0, while larger variants are CC BY-NC-4.0. This records the project’s statement, not a blanket conclusion about every training source or future redistribution scenario. The metric model is fine-tuned on Virtual KITTI 2; the training-dataset terms and any converted-artifact redistribution obligations remain separate compliance items.

## Why qualification stopped

The local development environment has no usable `python` command or installed PyTorch runtime, so the official checkpoint could not be loaded and real-image inference could not be executed. No checkpoint was downloaded, no SHA-256 was produced, and no private/user evidence was used. The official project does not provide a ready-made TFLite/LiteRT artifact in the documented download path. Therefore the mandatory real-artifact inference, output-decoding, and mobile-feasibility gates are not satisfied.

No contract was created under `datasets/manifests/depth/`, and no depth artifact was added to the repository.

## Future deterministic integration direction

If separately qualified later, the safer V0 choice is likely the relative Small model for scene ordering, unless an independently verified mobile conversion of the outdoor metric Small model is established. Any metric output must be described as `model-estimated depth`, not measured distance. Sampling depth inside TASK 007 boxes should use a robust interior statistic rather than a box-center pixel; without TASK 008 masks, box contents can include background and the result has object-association uncertainty.

TASK 009A should not proceed to Android integration until an isolated environment can load the exact official checkpoint, run real road/vehicle/incident photographs, verify finite nontrivial output and depth direction, and establish a supported TFLite/LiteRT or other offline mobile route with source-vs-deployable parity.
