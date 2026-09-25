# IRIS Engineering Rules

These rules are permanent project controls for IRIS (Incident Reconstruction & Intelligence System). Every future task must read this file first, inspect the repository, make the smallest necessary change, preserve working functionality, add appropriate tests, format code, run static analysis, run relevant tests, build Android when applicable, fix task-caused failures, and update status only after verification.

## Product and implementation principles

- IRIS is a production-oriented, offline-first Android application.
- Do not create implementation code, projects, models, datasets, sample cases, or future feature scaffolding unless the task explicitly requires it.
- Modify only what is necessary. Do not silently swallow errors or delete legitimate failing tests to obtain a green run.
- Do not mark functionality complete merely because code exists.

## Absolute real-data rule

IRIS must not fake functionality. Production code must never contain or display mock analytical data, fake accident detections, fabricated AI results, hard-coded or random confidence values, fake GPS coordinates or locations, fake measurements, vehicle speeds, physics results, canned scenarios presented as generated results, fake evidence, fake reconstructions, fake report findings, placeholder analytical values presented as real, or static JSON pretending to be model output.

Mocks, fakes, fixtures, and test doubles are permitted only inside automated tests. If functionality is not implemented, production must return an explicit state such as `UNAVAILABLE` or `UNSUPPORTED`. If evidence is insufficient, return `INSUFFICIENT_EVIDENCE`; if a value cannot be determined, return `UNKNOWN`. Honest unavailability is preferable to fabricated functionality.

## Data provenance

Important analytical values must eventually carry one of these provenance categories:

`OBSERVED`, `MEASURED`, `METADATA`, `MAP_DERIVED`, `MODEL_ESTIMATED`, `PHYSICS_DERIVED`, `USER_ENTERED`, `ASSUMED`, `UNKNOWN`.

## Evidence integrity

Original evidence must eventually be immutable. The conceptual flow is: external evidence -> application-controlled original -> SHA-256 -> immutable evidence record -> derivative working copy -> analysis. Analysis must never overwrite original evidence.

## AI rules

Production AI adapters must execute real bundled model files. Never emulate a model with hard-coded conditions, random numbers, static JSON, filenames, or demo responses. A missing model must produce an explicit unavailable/error state, and inference failures must not produce fabricated results.

## Physics and scenarios

Physics must use deterministic, testable calculations; an LLM is not the numerical physics engine. Uncertain inputs must propagate uncertainty, and unjustified numerical precision must not be manufactured.

Scenarios are hypotheses, not established truth. Future scenario generation must use observed evidence, road geometry, vehicle positions, damage evidence, skid/debris evidence where available, measurements, and physics constraints. IRIS may produce zero, one, two, or three viable scenarios. Never fabricate scenarios to fill a UI, and never display fake probability percentages.

## Location rules

Users must not normally type latitude/longitude. Supported approaches are EXIF GPS, location search, map pin, current device location, and unknown/skip. Current phone location must never automatically be assumed to be the incident location. Missing GPS must never result in invented coordinates.

## Offline-first rule

Core functionality must not require a development laptop, localhost, cloud GPU, OpenAI API, Gemini API, Claude API, or paid API. Internet may support map/geocoding functionality where necessary; core analysis should remain local.

## Validation and delivery discipline

Validate behavior with appropriate automated tests and real-data/error-state checks. Inspect changes and relevant outputs before reporting completion. For documentation-only tasks, document checks performed and state when code tests are not applicable. Every status claim must be supported by verification.
