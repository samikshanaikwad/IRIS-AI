# IRIS — Incident Reconstruction & Intelligence System

IRIS is an offline-first Android application in development for incident reconstruction and intelligence from real evidence.

## Current status

The Flutter source foundation is established under `app/`. Static analysis and widget tests pass, but Android APK validation is blocked until a local Android SDK and compatible Java runtime are installed. No incident analysis, AI, evidence import, location, mapping, database, physics, reconstruction, or reporting feature exists yet.

## Real-data principle

IRIS must never present fabricated, mock, or placeholder analytical information as real. When a future capability is unavailable or evidence is insufficient, the application must report an explicit truthful state. See [AGENTS.md](AGENTS.md) for the permanent engineering rules.

## Repository structure

```
IRIS/
├── AGENTS.md                 # Permanent engineering rules
├── README.md
├── app/                      # Flutter Android application foundation
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

Once `app/` has been generated and Flutter/Android tooling is available, run from `app/`:

```powershell
flutter pub get
flutter run
flutter analyze
flutter test
flutter build apk --debug
```

The debug APK will be produced at `app/build/app/outputs/flutter-apk/app-debug.apk` after a successful build.

## Foundation-only warning

This repository does not currently implement any IRIS analytical or reconstruction functionality. Do not interpret this project state as providing incident results or evidence analysis.
