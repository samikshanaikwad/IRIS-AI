import 'package:sqflite/sqflite.dart';

import '../database_constants.dart';

Future<void> migrateDatabase(
  Database database,
  int fromVersion,
  int toVersion,
) async {
  for (int version = fromVersion + 1; version <= toVersion; version++) {
    switch (version) {
      case 1:
        await _createVersionOne(database);
      case 2:
        await _createVersionTwo(database);
      default:
        throw StateError(
          'No database migration registered for version $version.',
        );
    }
  }
}

Future<void> _createVersionTwo(Database database) async {
  final List<Map<String, Object?>> casesTable = await database.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
    <Object?>[IrisDatabaseConstants.casesTable],
  );
  if (casesTable.length != 1) {
    throw StateError(
      'Cannot migrate IRIS database to version 2 without the version 1 cases table.',
    );
  }

  await database.execute('''
    CREATE TABLE ${IrisDatabaseConstants.evidenceTable} (
      id TEXT PRIMARY KEY NOT NULL,
      case_id TEXT NOT NULL,
      stored_relative_path TEXT NOT NULL UNIQUE,
      original_display_name TEXT,
      source_type TEXT NOT NULL CHECK(source_type IN ('camera', 'gallery')),
      captured_at INTEGER,
      imported_at INTEGER NOT NULL,
      mime_type TEXT,
      width_px INTEGER CHECK(width_px IS NULL OR width_px > 0),
      height_px INTEGER CHECK(height_px IS NULL OR height_px > 0),
      file_size_bytes INTEGER NOT NULL CHECK(file_size_bytes >= 0),
      sha256 TEXT NOT NULL CHECK(length(sha256) = 64),
      FOREIGN KEY(case_id) REFERENCES ${IrisDatabaseConstants.casesTable}(id)
        ON DELETE CASCADE,
      UNIQUE(case_id, sha256)
    )
  ''');

  await database.execute('''
    CREATE INDEX ${IrisDatabaseConstants.evidenceCaseIndex}
    ON ${IrisDatabaseConstants.evidenceTable} (
      case_id,
      imported_at ASC,
      id ASC
    )
  ''');
}

Future<void> _createVersionOne(Database database) async {
  await database.execute('''
    CREATE TABLE ${IrisDatabaseConstants.casesTable} (
      id TEXT PRIMARY KEY NOT NULL,
      title TEXT NOT NULL CHECK(length(trim(title)) BETWEEN 1 AND 120),
      status TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      incident_occurred_at INTEGER,
      notes TEXT
    )
  ''');

  await database.execute('''
    CREATE INDEX ${IrisDatabaseConstants.casesUpdatedAtIndex}
    ON ${IrisDatabaseConstants.casesTable} (
      updated_at DESC,
      created_at DESC,
      id ASC
    )
  ''');
}
