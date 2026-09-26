# IRIS — Incident Reconstruction & Intelligence System

IRIS is an offline-first Android application in development for incident reconstruction and intelligence from real evidence.

## Current status

The verified Flutter Android foundation and production application shell are established under `app/`. The current application includes the IRIS dark design system, four-destination navigation, and real offline SQLite case management. Users can create, list, open, rename, and delete case metadata; Home and Cases are driven by persisted records. Evidence acquisition and all analytical capabilities remain unavailable.

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

The debug APK will be produced at `app/build/app/outputs/flutter-apk/app-debug.apk` after a successful build. Case operations use the local `iris.db` SQLite database and require no network connection. See [docs/CASE_DATABASE.md](docs/CASE_DATABASE.md) for the schema and migration rules.

## Current-scope warning

This repository currently provides the application foundation, design system, navigation shell, and local case metadata lifecycle. It does not acquire evidence or implement IRIS analytical, location, reconstruction, physics, scenario, or reporting functionality and must not be interpreted as providing incident results or evidence analysis.
