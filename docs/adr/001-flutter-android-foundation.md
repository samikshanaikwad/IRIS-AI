# 001 — Flutter Android Foundation

- Status: accepted
- Date: 2026-09-25
- Related phase: 01 Repository / Flutter foundation

## Context

IRIS needs a maintainable Android application foundation that can later host offline-first evidence workflows and justified native integrations. The permanent real-data, evidence-integrity, provenance, deterministic-physics, and offline-first rules in `AGENTS.md` apply to all later decisions.

## Decision

- Use Flutter and Dart for the mobile application.
- Treat Android as the current deployment target.
- Use Kotlin for Android-native integration.
- Require Android API 24 as the minimum SDK; do not lower it without a superseding ADR.
- Keep Flutter-managed current compile and target SDK values unless a demonstrated compatibility reason requires an explicit override.
- Store the Flutter application under `app/` so repository-level governance, documentation, ML, native modules, benchmarks, and tools remain separate.
- Reserve `native/` for small, justified platform modules that cannot reasonably live in Flutter/Dart.
- Preserve an offline-first direction: core capabilities must not depend on a development laptop, localhost, cloud GPU, or paid/cloud AI service.
- Add only dependencies required by implemented functionality. Foundation work must not pre-install database, camera, media import, maps, location, ML, vision, PDF, 3D, or physics packages.

## Alternatives considered

- Native Android-only application: deferred because Flutter is the planned cross-platform application layer.
- Adding anticipated dependencies immediately: rejected because unused packages expand maintenance, build, privacy, and dependency risk without delivering verified functionality.
- Placing the app at repository root: rejected because it would intermingle the application with project governance and future non-application assets.

## Consequences

Future application work begins within `app/`; native code needs an explicit technical justification. Android API 24 excludes older devices but provides a practical baseline for the planned application. Dependency additions require task-specific justification, implementation, and validation.
