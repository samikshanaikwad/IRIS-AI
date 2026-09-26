# ADR 005 — Deterministic Evidence Quality Assessment

- Status: accepted
- Date: 2026-09-27
- Related phases: 05 Camera / evidence quality

## Context

Later IRIS analysis needs a truthful technical preflight for real managed evidence. Phone images may be very large, original bytes must remain immutable, and quality labels must be explainable rather than opaque confidence scores. Existing v2 databases and real evidence must migrate without re-import or data loss.

## Decision

IRIS uses Flutter's bundled offline image codec and a deterministic Dart quality engine identified as `iris-image-quality-v1`. SHA-256 is recalculated by streaming the complete managed original. Original dimensions come from the encoded image descriptor. Pixel metrics use an aspect-preserving decoded representation with a maximum 1024-pixel edge. BT.709 mean luma, near-black/near-white fractions, and variance of the four-neighbor luma Laplacian are calculated from that bounded representation.

Thresholds and readiness rules are centralized and documented as initial IRIS application thresholds requiring later calibration. Results contain typed findings and are persisted as the latest assessment in schema v3. A fresh full-file hash and algorithm version determine whether a persisted result is current. Existing evidence has no fabricated migration result and appears as not assessed until the user performs a real check.

The v2-to-v3 migration creates `evidence_quality_assessments` with a cascading foreign key to `evidence_images`. It preserves every existing case, evidence row, managed path, and import-time digest. No new dependency or native Flutter plugin is introduced.

## Alternatives considered

- One opaque quality score: rejected because it hides measurements and encourages confidence-like interpretation.
- Decode every original at full resolution: rejected because modern phone images can create unnecessary memory pressure.
- OpenCV/native image processing: rejected because the required deterministic metrics do not justify another native dependency.
- Recalculate on every widget build: rejected because persisted results avoid repeated decode and compute work.
- Automatically replace a mismatched hash: rejected because it would destroy the import-time integrity reference.

## Consequences

- Quality checks are offline, reproducible, inspectable, and based on actual bytes and pixels.
- Original evidence remains unchanged while metric memory is bounded by the 1024-pixel analysis edge.
- Persisted results can be invalidated by algorithm or byte changes and explicitly reassessed.
- Initial thresholds are engineering defaults, not evidence-admissibility or forensic-validity standards.
- The feature makes no accident, causation, reconstruction, or AI inference claim.
