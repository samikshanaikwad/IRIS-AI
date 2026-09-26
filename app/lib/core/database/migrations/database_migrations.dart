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
      default:
        throw StateError(
          'No database migration registered for version $version.',
        );
    }
  }
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
