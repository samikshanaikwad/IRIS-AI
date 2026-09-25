# IRIS Master Specification

## Objective

IRIS (Incident Reconstruction & Intelligence System) will be a real offline-first Android application for reconstructing incidents from one or more real images while preserving evidence integrity, exposing uncertainty, and avoiding fabricated analytical output.

## Major final features

- Import and capture 1 to N real incident images.
- Determine whether evidence depicts an accident/incident and stop reconstruction for non-incident evidence.
- Analyze vehicles, roads, damage, and scene evidence.
- Treat single-image reconstruction as a first-class workflow and support multi-image reconstruction when views exist.
- Obtain location from EXIF, search, map selection, or user-confirmed current location without normally requiring coordinate entry.
- Reconstruct an approximate 3D scene with professional low-poly/voxel surroundings.
- Generate physically constrained candidate scenarios, visualize trajectories/timelines, and compare scenarios against evidence.
- Perform deterministic physics calculations and report assumptions, uncertainty, and contradictions.
- Generate an AI-assisted local PDF report.
- Store cases and evidence locally, preserve original evidence integrity, and support core functionality without the development laptop or internet.

## Planned technology stack

Flutter and Dart on Android; SQLite; LiteRT/TFLite for on-device inference; PyTorch for model training/fine-tuning; OpenCV where appropriate; MapLibre with OpenStreetMap-derived data; GLB/glTF assets; deterministic Dart/C++ physics; local Android storage; SHA-256 evidence integrity; and local PDF generation. No paid or cloud AI API is required for core functionality.

## High-level pipeline

Evidence intake and immutable hashing -> evidence quality and metadata -> incident classification -> detection/segmentation/damage and scene intelligence -> location and geometry -> measurements/calibration and depth -> 3D scene -> deterministic physics -> zero to three viable scenario hypotheses -> evidence comparison and explainability -> local report/export.

## Single-image requirement

One real image must be a supported first-class workflow. The system must not require multiple views before it can assess evidence or produce an honest result. Where one image is insufficient, it must report `INSUFFICIENT_EVIDENCE`, `UNKNOWN`, `UNAVAILABLE`, or `UNSUPPORTED` as appropriate rather than inventing geometry or measurements.

## Multi-image requirement

When multiple real views exist, IRIS may use them for stronger geometry and consistency analysis. It must preserve each original independently, track associations and provenance, and report contradictions or insufficient overlap instead of forcing a reconstruction.

## Real-data rule

Production must never present mock, fake, fabricated, random, hard-coded, canned, or placeholder analytical values as real. Mocks and fixtures are allowed only in automated tests. Missing capability, missing models, failed inference, and insufficient evidence must produce explicit states.

## Offline-first rule

Core case management, evidence handling, analysis orchestration, model inference, physics, scenario evaluation, and report generation are intended to run locally. Network access may be used for map/geocoding functions, but the application must not depend on a laptop, localhost, cloud GPU, or paid AI service.

## Evidence integrity and provenance

External evidence becomes an application-controlled immutable original, is hashed with SHA-256, and is analyzed only through derivative working copies. Important values carry provenance: `OBSERVED`, `MEASURED`, `METADATA`, `MAP_DERIVED`, `MODEL_ESTIMATED`, `PHYSICS_DERIVED`, `USER_ENTERED`, `ASSUMED`, or `UNKNOWN`.

## Physics and scenario philosophy

Scenarios are hypotheses, never established truth. Candidate generation must be constrained by evidence, geometry, positions, damage, available skid/debris evidence, measurements, and deterministic physics. Uncertainty must propagate, unjustified precision must be avoided, and zero, one, two, or three viable scenarios are valid outcomes. Probability percentages must not be fabricated.

## Validation philosophy

Validation combines unit, integration, model, physics, evidence-integrity, offline, failure-state, performance, end-to-end, and release checks. Tests must use mocks/fixtures only as test inputs. Production behavior must be verified to fail honestly when evidence, models, location, or required capability is unavailable. A feature is complete only after relevant analysis, tests, formatting, build, and status verification succeed.
