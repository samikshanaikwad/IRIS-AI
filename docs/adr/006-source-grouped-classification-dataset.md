# ADR 006 — Provenance-Preserving Classification Dataset Pipeline

- Status: accepted
- Date: 2026-09-27
- Related phase: 08 Incident classifier (dataset preparation only)

## Context

TASK 006 needs real still images for a future accident-versus-non-accident
classifier. Video-derived adjacent frames are highly correlated, DoTA's
anomaly start can precede visible impact, its official clip split shares many
original videos across train and validation, and the repository's software
license does not establish the usage rights for video content or derived
frames. A random image split would produce leakage and misleading evaluation.

## Decision

IRIS uses versioned source-registry, label, extraction, and split policies. A
manifest row retains source dataset/version, original video group, event,
frame, label basis, license status, full-byte SHA-256, decoded dimensions, and
64-bit dHash. Raw and derived media stay local and Git-ignored.

The fundamental DoTA split unit is the original source video, not an extracted
frame or clip. A deterministic seed targets a 70/15/15 train/validation/test
group allocation. A separate `external_test` designation is preserved.

DoTA accident candidates require a human-reviewed collision-visible window.
Non-accident candidates require a separate human-reviewed normal window that
ends before a configurable transition buffer. Sampling is bounded and spaced,
and copies preserve source bytes. Exact cross-split duplicates and source-group
leakage are errors; dHash identifies near-duplicate candidates for review.

Source use and extraction are blocked while dataset-content and derived-frame
permissions remain `REVIEW_REQUIRED`. The code repository's MIT license is
recorded separately and does not approve dataset content.

## Alternatives considered

- Randomly split extracted frames: rejected because adjacent frames and clips
  from one source video would leak across evaluation boundaries.
- Treat every frame after `anomaly_start` as accident: rejected because DoTA
  starts an anomaly when it becomes inevitable, not necessarily when impact is
  visible.
- Treat every sufficiently early frame as non-accident without review:
  rejected because time alone does not prove what a still image depicts.
- Use a repository software license as content permission: rejected because
  code and dataset rights are distinct.
- Seed synthetic or scraped images to exercise the pipeline: rejected by the
  IRIS real-data and provenance rules; tests instead use temporary fixtures.

## Consequences

- Real acquisition and legal review remain blockers; no model can yet be
  trained.
- Human semantic review is required but prevents automatic ambiguous labels.
- Group-level splitting may deviate from exact image-count ratios.
- Dataset integrity and leakage checks are deterministic and reproducible.
- This decision changes no Flutter, Android, SQLite, or production inference
  code.
