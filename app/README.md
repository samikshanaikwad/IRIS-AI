# IRIS Flutter Application

This directory contains the Android-focused, offline-first IRIS application.

IRIS stores user-confirmed cases and managed evidence locally. It preserves imported originals, records evidence SHA-256 values, and persists deterministic image-quality assessments. The SQLite database is `iris.db`, currently schema v4; its v3 → v4 migration adds per-evidence classification records without deleting cases, evidence, or quality assessments.

## Experimental V0 image classification

For individually stored images whose quality assessment is current and usable, IRIS can run the bundled offline MobileNetV3Small V0 TFLite classifier. It verifies the managed original's SHA-256 before inference, uses RGB aspect-preserving containment on a centered black 224×224 canvas, applies ImageNet normalization, and executes float32 NHWC TFLite inference. The raw output is a logit; IRIS applies sigmoid outside the model and labels the resulting **model score** using the frozen threshold `0.8611480594`.

Each result is persisted with evidence bytes, model/contract hashes, raw logit, model score, threshold, label, and timestamp. Results become stale if the evidence or model provenance no longer matches. Classification is unavailable for not-assessed/stale quality, blocked for not-usable quality, and allowed with an explicit limitation notice for usable-with-limitations quality.

The V0 classifier is experimental and non-production. Its AccidentDetection-9k source remains `REVIEW_REQUIRED` because individual underlying-image provenance is unresolved; it is not a forensic conclusion, calibrated probability, or case-level result. No cloud inference, fake score, or fallback classification is used.

Run from this directory with the documented Flutter, Android SDK, and JDK 17 toolchain:

```powershell
flutter run
flutter analyze
flutter test
flutter build apk --debug
```
