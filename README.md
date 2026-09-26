# IRIS — Incident Reconstruction & Intelligence System

IRIS is an offline-first Android application in development for incident reconstruction and intelligence from real evidence.

## Current status

The verified Flutter Android foundation and production application shell are established under `app/`. The application includes the IRIS dark design system, four-destination navigation, real offline SQLite case management, and human-accepted local camera/gallery acquisition. A case can own real images copied unchanged into app-private storage with persisted metadata and SHA-256 integrity identifiers. Deterministic offline evidence-quality assessment is implemented pending TASK 005 human acceptance.

## Real-data principle

IRIS must never present fabricated, mock, or placeholder analytical information as real. When a future capability is unavailable or evidence is insufficient, the application must report an explicit truthful state. See [AGENTS.md](AGENTS.md) for the permanent engineering rules.

## Repository structure

```
IRIS/
├── AGENTS.md                 # Permanent engineering rules
├── README.md
├── app/                      # Flutter Android application and local case persistence
├── native/                   # Reserved for justified native modules
├── ml/                       # Model training/configuration source, not model outputs
├── datasets/                 # Dataset documentation/configuration, no committed large data
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

## Current-scope warning

This repository currently provides the application foundation, design system, navigation shell, local case lifecycle, real local image acquisition/storage, and deterministic technical image-quality measurements. Quality readiness is not accident analysis or forensic validation. IRIS does not yet implement incident classification, location, reconstruction, physics, scenarios, or reports and must not be interpreted as providing incident conclusions.
