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
      case 3:
        await _createVersionThree(database);
      case 4:
        await _createVersionFour(database);
      case 5:
        await _createVersionFive(database);
      default:
        throw StateError(
          'No database migration registered for version $version.',
        );
    }
  }
}

Future<void> _createVersionFive(Database database) async {
  await database.execute('''
    CREATE TABLE ${IrisDatabaseConstants.evidenceDetectionAnalysesTable} (
      id TEXT PRIMARY KEY NOT NULL,
      evidence_id TEXT NOT NULL,
      evidence_sha256 TEXT NOT NULL CHECK(length(evidence_sha256) = 64),
      detector_id TEXT NOT NULL,
      detector_sha256 TEXT NOT NULL CHECK(length(detector_sha256) = 64),
      contract_version TEXT NOT NULL,
      status TEXT NOT NULL CHECK(status IN ('complete', 'error')),
      analyzed_at INTEGER NOT NULL,
      inference_ms INTEGER,
      FOREIGN KEY(evidence_id) REFERENCES ${IrisDatabaseConstants.evidenceTable}(id) ON DELETE CASCADE
    )
  ''');
  await database.execute('''
    CREATE TABLE ${IrisDatabaseConstants.evidenceDetectionsTable} (
      id TEXT PRIMARY KEY NOT NULL,
      analysis_id TEXT NOT NULL,
      detection_index INTEGER NOT NULL,
      class_id INTEGER NOT NULL,
      class_name TEXT NOT NULL,
      detection_score REAL NOT NULL CHECK(detection_score >= 0.0 AND detection_score <= 1.0),
      ymin REAL NOT NULL CHECK(ymin >= 0.0 AND ymin <= 1.0),
      xmin REAL NOT NULL CHECK(xmin >= 0.0 AND xmin <= 1.0),
      ymax REAL NOT NULL CHECK(ymax >= 0.0 AND ymax <= 1.0),
      xmax REAL NOT NULL CHECK(xmax >= 0.0 AND xmax <= 1.0),
      FOREIGN KEY(analysis_id) REFERENCES ${IrisDatabaseConstants.evidenceDetectionAnalysesTable}(id) ON DELETE CASCADE,
      UNIQUE(analysis_id, detection_index)
    )
  ''');
}

Future<void> _createVersionFour(Database database) async {
  await database.execute('''
    CREATE TABLE ${IrisDatabaseConstants.evidenceClassificationTable} (
      evidence_id TEXT PRIMARY KEY NOT NULL,
      evidence_sha256 TEXT NOT NULL CHECK(length(evidence_sha256) = 64),
      model_id TEXT NOT NULL,
      model_tflite_sha256 TEXT NOT NULL CHECK(length(model_tflite_sha256) = 64),
      model_contract_version TEXT NOT NULL,
      raw_logit REAL NOT NULL,
      model_score REAL NOT NULL CHECK(model_score >= 0.0 AND model_score <= 1.0),
      threshold REAL NOT NULL CHECK(threshold >= 0.0 AND threshold <= 1.0),
      classification_label TEXT NOT NULL CHECK(classification_label IN ('accident', 'non_accident')),
      analyzed_at INTEGER NOT NULL,
      FOREIGN KEY(evidence_id)
        REFERENCES ${IrisDatabaseConstants.evidenceTable}(id)
        ON DELETE CASCADE
    )
  ''');
}

Future<void> _createVersionThree(Database database) async {
  final List<Map<String, Object?>> evidenceTable = await database.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
    <Object?>[IrisDatabaseConstants.evidenceTable],
  );
  if (evidenceTable.length != 1) {
    throw StateError(
      'Cannot migrate IRIS database to version 3 without the version 2 evidence table.',
    );
  }

  await database.execute('''
    CREATE TABLE ${IrisDatabaseConstants.evidenceQualityTable} (
      evidence_id TEXT PRIMARY KEY NOT NULL,
      assessed_at INTEGER NOT NULL,
      algorithm_version TEXT NOT NULL,
      expected_sha256 TEXT NOT NULL CHECK(length(expected_sha256) = 64),
      assessed_sha256 TEXT CHECK(
        assessed_sha256 IS NULL OR length(assessed_sha256) = 64
      ),
      file_state TEXT NOT NULL CHECK(
        file_state IN ('available', 'missing', 'unreadable')
      ),
      decode_state TEXT NOT NULL CHECK(
        decode_state IN ('decoded', 'failed', 'not_attempted')
      ),
      integrity_state TEXT NOT NULL CHECK(
        integrity_state IN ('verified', 'mismatch', 'unavailable')
      ),
      readiness_state TEXT NOT NULL CHECK(
        readiness_state IN ('ready', 'usable_with_limitations', 'not_usable')
      ),
      file_size_bytes INTEGER CHECK(
        file_size_bytes IS NULL OR file_size_bytes >= 0
      ),
      original_width INTEGER CHECK(
        original_width IS NULL OR original_width > 0
      ),
      original_height INTEGER CHECK(
        original_height IS NULL OR original_height > 0
      ),
      analysis_width INTEGER CHECK(
        analysis_width IS NULL OR analysis_width > 0
      ),
      analysis_height INTEGER CHECK(
        analysis_height IS NULL OR analysis_height > 0
      ),
      orientation TEXT CHECK(
        orientation IS NULL OR orientation IN ('portrait', 'landscape', 'square')
      ),
      sharpness_value REAL,
      mean_luminance REAL,
      dark_clipped_fraction REAL CHECK(
        dark_clipped_fraction IS NULL OR
        dark_clipped_fraction BETWEEN 0.0 AND 1.0
      ),
      bright_clipped_fraction REAL CHECK(
        bright_clipped_fraction IS NULL OR
        bright_clipped_fraction BETWEEN 0.0 AND 1.0
      ),
      findings_json TEXT NOT NULL,
      FOREIGN KEY(evidence_id)
        REFERENCES ${IrisDatabaseConstants.evidenceTable}(id)
        ON DELETE CASCADE
    )
  ''');
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
