# 003 — Production Android Plugin Registration

- Status: accepted
- Date: 2026-09-26
- Related phase: 03 Database / case management
- Supersedes: the Android registration correction in ADR 002

## Context

IRIS depends on the Android implementation of `sqflite` for production case persistence. A generated `GeneratedPluginRegistrant` built while Flutter plugin metadata omitted `sqflite_android` allowed the application to compile and launch but left the production `MainActivity` engine without the `com.tekartik.sqflite` method-channel handler. A separate integration-test build had generated a registrant containing sqflite, so that test did not prove the registration state of the production artifact later installed by the operator.

Flutter 3.35.7 creates the implicit `FlutterActivity` engine with constructor-level automatic registration disabled and then calls `FlutterActivity.configureFlutterEngine`. The base implementation uses `GeneratedPluginRegister` to invoke the app's generated registrant reflectively. IRIS does not provide or cache a custom engine and does not define a custom Android `Application`.

## Decision

- Keep Flutter's generated `GeneratedPluginRegistrant` as the single plugin list.
- Override `MainActivity.configureFlutterEngine` and directly call `GeneratedPluginRegistrant.registerWith(flutterEngine)` once. Do not call the base implementation as well, which would attempt duplicate registration.
- Do not import or instantiate `SqflitePlugin` directly. Plugin implementation selection remains controlled by Flutter's federated-plugin tooling.
- Fail Android builds when generated Flutter metadata omits `sqflite_android` or the generated registrant omits `SqflitePlugin`.
- In debug builds only, expose and log non-sensitive diagnostics proving that the generated registrant ran, the sqflite class is packaged, and the plugin is attached to the exact `MainActivity` engine.
- Verify `getDatabasesPath`, production application composition, case creation, readback, and reopen persistence on that engine using an isolated integration-test database.

## Alternatives considered

- Rely only on inherited reflective registration: rejected for this project because reflection failures and stale generated registrants can fail silently and already escaped validation.
- Instantiate `com.tekartik.sqflite.SqflitePlugin` directly: rejected because it bypasses Flutter's supported generated plugin list and couples application Kotlin source to one implementation package.
- Replace SQLite with in-memory storage or delete the database: rejected because both violate persistence and data-integrity requirements.

## Consequences

Plugin selection remains standard and generated, while invocation on the production engine is explicit and observable. A malformed generated plugin state now fails the Android build rather than becoming a runtime-only storage error. Debug diagnostics contain no database paths, case titles, record contents, or other user data. The production database schema and migration behavior are unchanged.
