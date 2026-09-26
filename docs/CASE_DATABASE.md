# IRIS Local Case Database

IRIS stores case metadata in an on-device SQLite database. The Flutter SDK does not provide a SQLite API, so the application uses `sqflite` for Android SQLite access and `path` to construct the platform database path safely. There is no network or cloud dependency in the case lifecycle.

## Database identity

- Filename: `iris.db`
- Current schema version: `1`
- Production location: the application database directory returned by `getDatabasesPath()`
- Production startup state: an empty `cases` table on a clean installation
- Sort order: `updated_at DESC`, then `created_at DESC`, then `id ASC`

Production startup never seeds, inserts, or synthesizes case records. A displayed case must originate from an explicit user-confirmed creation persisted through `CaseRepository`.

## Version 1 schema

```sql
CREATE TABLE cases (
  id TEXT PRIMARY KEY NOT NULL,
  title TEXT NOT NULL CHECK(length(trim(title)) BETWEEN 1 AND 120),
  status TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  incident_occurred_at INTEGER,
  notes TEXT
);

CREATE INDEX idx_cases_updated_at
ON cases (updated_at DESC, created_at DESC, id ASC);
```

`created_at`, `updated_at`, and the optional `incident_occurred_at` are UTC epoch milliseconds. Presentation converts them to device-local time. `incident_occurred_at` remains null until a user or later evidence workflow establishes that value; it is never inferred from case creation time.

The only creatable status in this phase is `draft`, displayed as `Draft`. Unknown future persisted status strings map defensively to `Unknown`; they are not silently treated as completed or analyzed.

Case IDs are UUIDv4-shaped 128-bit identifiers produced with Dart's cryptographically secure random source. They remain stable in SQLite and are suitable for future case-owned evidence directories without exposing a fabricated sequential case number.

## Application boundaries

- `IrisDatabase` owns opening, schema callbacks, versioning, and closing.
- `CaseRepository` defines case operations without exposing SQL to the UI.
- `SqliteCaseRepository` performs parameterized SQLite reads and writes.
- `IrisApplicationServices` is the application composition and lifetime boundary.
- `CaseController` distinguishes loading, data/empty, and storage-error states while treating the repository as the source of truth.

On Android, plugin registration uses Flutter's standard generated mechanism. `flutter pub get` resolves `sqflite` to `sqflite_android`, records that native implementation in `.flutter-plugins-dependencies`, and generates `GeneratedPluginRegistrant`. `MainActivity.configureFlutterEngine` invokes that generated registrant directly once; it does not import or instantiate an individual plugin implementation. The Android build fails if generated metadata or the registrant omits sqflite. Debug-only runtime diagnostics and an on-device production-path test additionally verify that the plugin is attached to the exact `MainActivity` engine and that `getDatabasesPath` responds.

After SQLite opens, `IrisDatabase` verifies both schema version 1 and the presence of the `cases` table. An inconsistent existing database fails explicitly and is not deleted or recreated. Debug builds print database initialization failures and repository operation stack traces; repository diagnostics omit case titles, SQL arguments, and record contents. Release builds retain the generic user-facing storage error without debug diagnostics.

User-provided titles are passed through SQLite binding arguments or map-based `sqflite` operations. They are never concatenated into SQL. Titles are whitespace-normalized, required, and limited to 120 characters while retaining legitimate punctuation.

## Migration convention

Every schema change must increment `IrisDatabaseConstants.schemaVersion` and add an explicit sequential migration in `migrations/database_migrations.dart`. Migrations run from each prior version through the target version and must preserve user records. Unknown migrations and downgrades fail explicitly; production must not delete and recreate the database as a fallback.

Database tests use isolated temporary SQLite files through `sqflite_common_ffi`. They never open, seed, or delete the production database.

## Future evidence storage

Version 1 stores case metadata only. Images are not stored as SQLite BLOBs, and no evidence files or directories are fabricated. A later evidence task may use the stable case ID for application-controlled paths such as `cases/<case-id>/originals/` and `cases/<case-id>/derivatives/`, while SQLite stores the corresponding evidence metadata and integrity records.
