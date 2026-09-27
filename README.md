# IRIS — Incident Reconstruction & Intelligence System

IRIS is an offline-first Android application in development for incident reconstruction and intelligence from real evidence.

## Current status

The verified Flutter Android foundation and production application shell are established under `app/`. The application includes the IRIS dark design system, four-destination navigation, real offline SQLite case management, human-accepted local camera/gallery acquisition, and human-accepted deterministic evidence-quality assessment. A case can own real images copied unchanged into app-private storage with persisted metadata and SHA-256 integrity identifiers.

TASK 006 has established a source-grouped classification dataset preparation and validation pipeline. No real classification dataset has been acquired or approved, and no classifier has been trained or integrated.

## Real-data principle

IRIS must never present fabricated, mock, or placeholder analytical information as real. When a future capability is unavailable or evidence is insufficient, the application must report an explicit truthful state. See [AGENTS.md](AGENTS.md) for the permanent engineering rules.

## Repository structure

```
IRIS/
├── AGENTS.md                 # Permanent engineering rules
├── README.md
├── app/                      # Flutter Android application and local case persistence
├── native/                   # Reserved for justified native modules
├── ml/                       # Dataset/model tooling and configuration, not model outputs
├── datasets/                 # Tracked policy/manifests; no committed large data
├── benchmarks/               # Benchmark definitions and documentation
├── tools/                    # Project utilities
├── tests/                    # Cross-application tests
└── docs/                     # Specifications, status, and ADRs
```

## Prerequisites

- Flutter SDK and bundled Dart SDK on `PATH`
- Android SDK with an API 24+ platform and build tools
- Java/JDK compatible with the installed Flutter/Android Gradle toolchain
- Android emulator or a USB-debuggable Android device to run the app

## Flutter commands

Run from `app/` with the documented Flutter/Android tooling available:

```powershell
flutter pub get
flutter run
flutter analyze
flutter test
flutter build apk --debug
```

The debug APK will be produced at `app/build/app/outputs/flutter-apk/app-debug.apk` after a successful build. Case, evidence, and deterministic quality operations use local SQLite and app-private files and require no network connection. See [docs/CASE_DATABASE.md](docs/CASE_DATABASE.md), [docs/EVIDENCE_ACQUISITION.md](docs/EVIDENCE_ACQUISITION.md), and [docs/EVIDENCE_QUALITY.md](docs/EVIDENCE_QUALITY.md) for persistence, integrity, and quality rules.

Classification dataset commands and policy are documented in [docs/CLASSIFICATION_DATASET.md](docs/CLASSIFICATION_DATASET.md). The current production manifest is intentionally empty and not training-eligible.

## Current-scope warning

This repository currently provides the application foundation, design system, navigation shell, local case lifecycle, real local image acquisition/storage, and deterministic technical image-quality measurements. Quality readiness is not accident analysis or forensic validation. IRIS does not yet implement incident classification, location, reconstruction, physics, scenarios, or reports and must not be interpreted as providing incident conclusions.
