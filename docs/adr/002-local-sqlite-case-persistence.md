# 002 — Local SQLite Case Persistence

- Status: accepted
- Date: 2026-09-26
- Related phase: 03 Database / case management

## Context

IRIS needs durable case metadata that remains available offline and across application, emulator, and device restarts. The UI must distinguish an empty database from a storage failure, must never fall back to fabricated records, and must provide stable identifiers for later evidence ownership. Flutter does not include a built-in SQLite API.

## Decision

- Store production case metadata in the Android application sandbox using SQLite through `sqflite`.
- Use `path` only to construct the platform-provided database path safely.
- Name the database `iris.db` and begin at explicit schema version 1.
- Keep SQL behind a `CaseRepository` abstraction with a separate `SqliteCaseRepository`; widgets do not execute SQL.
- Compose one database/repository lifetime through `IrisApplicationServices` without a dependency-injection framework.
- Store timestamps as UTC epoch milliseconds and convert them to local time only for display.
- Generate stable UUIDv4-shaped IDs from `Random.secure()` without adding a UUID package solely for this operation.
- Persist the factual `draft` status for new cases and map unrecognized future values to `Unknown`.
- Implement sequential, non-destructive migrations. Unknown upgrades and downgrades fail explicitly rather than deleting user data.
- Start every clean production database empty. No seed, demo, sample, or fallback case records are permitted.
- Use `sqflite_common_ffi` only as a development dependency so automated tests exercise real, isolated temporary SQLite databases on the host.

## Alternatives considered

- In-memory state, hard-coded JSON, or shared preferences: rejected because they do not provide the required relational durability, migration path, and transactional behavior.
- A cloud database or backend: rejected because case management is core offline functionality and must not require an account, internet access, or paid service.
- Drift or another ORM/code-generation stack: deferred because explicit SQL and one table are currently clearer and carry less build and maintenance complexity.
- Storing future evidence as SQLite BLOBs: rejected. This schema stores metadata only; future original and derivative evidence belongs in application-controlled files associated through the stable case ID.
- Destructive schema recreation: rejected because future migrations must preserve user cases.

## Consequences

Android gains a native SQLite plugin resolved through Flutter's standard plugin tooling but no Android toolchain version changes. Repository methods remain asynchronous and UI surfaces explicit loading, empty/data, and error states. Future schema work must add and test ordered migrations rather than editing version 1 in place after release. Evidence cleanup will need to extend the deletion workflow atomically when evidence storage is introduced; TASK 003 deletion removes only the case metadata record because no evidence store exists yet.

## Android registration correction — 2026-09-26

Manual emulator acceptance found generated plugin metadata that omitted `sqflite_android`; `GeneratedPluginRegistrant` therefore omitted `SqflitePlugin`, leaving the SQLite method channel without an Android handler. A temporary guarded import of `com.tekartik.sqflite.SqflitePlugin` in Kotlin was rejected after a clean build exposed that the plugin implementation was absent from `compileDebugKotlin` whenever the same generated dependency metadata was stale. It did not repair plugin discovery and made application Kotlin source depend directly on a generated plugin module.

IRIS uses Flutter's supported registration path instead: `sqflite` remains a production dependency, the Flutter plugin loader includes its resolved `sqflite_android` implementation, and the generated registrant attaches `com.tekartik.sqflite.SqflitePlugin` through the v2 embedding. `MainActivity` remains a plain `FlutterActivity`. Clean-build regression tests verify the Android plugin metadata, generated registrant class reference, and Flutter Gradle plugin wiring. The Android integration test exercises the actual method channel, fresh schema creation, and inserts before and after reopening an isolated test database.

The production-engine registration mechanism in this section is superseded by [ADR 003](003-production-android-plugin-registration.md), which records the later runtime finding and explicit generated-registrant invocation.
