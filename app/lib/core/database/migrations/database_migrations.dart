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
      case 6:
        await _createVersionSix(database);
      case 7:
        await _createVersionSeven(database);
      case 8:
        await _createVersionEight(database);
      case 9:
        await _createVersionNine(database);
      case 10:
        await _createVersionTen(database);
      case 11:
        await _createVersionEleven(database);
      case 12:
        await _createVersionTwelve(database);
      case 13:
        await _createVersionThirteen(database);
      case 14:
        await _createVersionFourteen(database);
      case 15:
        await database.execute(
          "ALTER TABLE ${IrisDatabaseConstants.environmentContextsTable} ADD COLUMN sources_json TEXT NOT NULL DEFAULT '[]'",
        );
      case 16:
        await _createVersionSixteen(database);
      case 17:
        await _createVersionSeventeen(database);
      default:
        throw StateError(
          'No database migration registered for version $version.',
        );
    }
  }
}

Future<void> _createVersionSeventeen(Database database) async {
  for (final table in <String>[
    IrisDatabaseConstants.evidenceDetectionAnalysesTable,
    IrisDatabaseConstants.evidenceDepthAnalysesTable,
  ]) {
    final columns = await database.rawQuery('PRAGMA table_info($table)');
    final names = columns.map((row) => row['name']).toSet();
    if (!names.contains('coordinate_contract_version')) {
      await database.execute(
        'ALTER TABLE $table ADD COLUMN coordinate_contract_version TEXT',
      );
    }
    if (!names.contains('coordinate_metadata_json')) {
      await database.execute(
        'ALTER TABLE $table ADD COLUMN coordinate_metadata_json TEXT',
      );
    }
  }
}

Future<void> _createVersionSixteen(Database database) async {
  final columns = await database.rawQuery(
    'PRAGMA table_info(${IrisDatabaseConstants.evidenceWorldAlignmentsTable})',
  );
  final names = columns.map((row) => row['name']).toSet();
  if (!names.contains('world_frame_fingerprint')) {
    await database.execute(
      'ALTER TABLE ${IrisDatabaseConstants.evidenceWorldAlignmentsTable} '
      'ADD COLUMN world_frame_fingerprint TEXT '
      'CHECK(world_frame_fingerprint IS NULL OR length(world_frame_fingerprint) = 64)',
    );
  }
  if (!names.contains('provenance_version')) {
    await database.execute(
      'ALTER TABLE ${IrisDatabaseConstants.evidenceWorldAlignmentsTable} '
      'ADD COLUMN provenance_version TEXT',
    );
  }
}

Future<void> _createVersionTwelve(Database database) async {
  await database.execute('''
    CREATE TABLE ${IrisDatabaseConstants.environmentContextsTable} (
      case_id TEXT PRIMARY KEY NOT NULL,
      provider TEXT NOT NULL,
      retrieved_at INTEGER NOT NULL,
      status TEXT NOT NULL CHECK(status IN ('AVAILABLE', 'EMPTY', 'UNAVAILABLE')),
      features_json TEXT NOT NULL,
      FOREIGN KEY(case_id) REFERENCES ${IrisDatabaseConstants.casesTable}(id) ON DELETE CASCADE
    )
  ''');
}

Future<void> _createVersionThirteen(Database database) async {
  await database.execute(
    'ALTER TABLE ${IrisDatabaseConstants.environmentContextsTable} ADD COLUMN latitude REAL NOT NULL DEFAULT 0.0',
  );
  await database.execute(
    'ALTER TABLE ${IrisDatabaseConstants.environmentContextsTable} ADD COLUMN longitude REAL NOT NULL DEFAULT 0.0',
  );
}

Future<void> _createVersionFourteen(Database database) async {
  await database.execute(
    'ALTER TABLE ${IrisDatabaseConstants.environmentContextsTable} ADD COLUMN provider_state TEXT NOT NULL DEFAULT \'UNKNOWN\'',
  );
}

Future<void> _createVersionEight(Database database) async {
  await database.execute('''
    CREATE TABLE ${IrisDatabaseConstants.multiViewPairAnalysesTable} (
      id TEXT PRIMARY KEY NOT NULL,
      case_id TEXT NOT NULL,
      evidence_a_id TEXT NOT NULL,
      evidence_b_id TEXT NOT NULL,
      evidence_a_sha256 TEXT NOT NULL CHECK(length(evidence_a_sha256) = 64),
      evidence_b_sha256 TEXT NOT NULL CHECK(length(evidence_b_sha256) = 64),
      algorithm_version TEXT NOT NULL,
      orb_policy TEXT NOT NULL,
      matching_policy TEXT NOT NULL,
      geometric_policy TEXT NOT NULL,
      feature_count_a INTEGER NOT NULL CHECK(feature_count_a >= 0),
      feature_count_b INTEGER NOT NULL CHECK(feature_count_b >= 0),
      candidate_match_count INTEGER NOT NULL CHECK(candidate_match_count >= 0),
      accepted_match_count INTEGER NOT NULL CHECK(accepted_match_count >= 0),
      verified_inlier_count INTEGER NOT NULL CHECK(verified_inlier_count >= 0),
      inlier_ratio REAL NOT NULL CHECK(inlier_ratio >= 0.0 AND inlier_ratio <= 1.0),
      geometric_model TEXT NOT NULL,
      status TEXT NOT NULL CHECK(status IN ('VERIFIED_CORRESPONDENCE', 'INSUFFICIENT_FEATURES', 'INSUFFICIENT_MATCHES', 'GEOMETRIC_VERIFICATION_FAILED', 'ERROR')),
      correspondence_json TEXT NOT NULL,
      analyzed_at INTEGER NOT NULL,
      FOREIGN KEY(case_id) REFERENCES ${IrisDatabaseConstants.casesTable}(id) ON DELETE CASCADE,
      FOREIGN KEY(evidence_a_id) REFERENCES ${IrisDatabaseConstants.evidenceTable}(id) ON DELETE CASCADE,
      FOREIGN KEY(evidence_b_id) REFERENCES ${IrisDatabaseConstants.evidenceTable}(id) ON DELETE CASCADE,
      CHECK(evidence_a_id <> evidence_b_id),
      UNIQUE(evidence_a_id, evidence_b_id)
    )
  ''');
}

Future<void> _createVersionNine(Database database) async {
  await database.execute('''
    CREATE TABLE ${IrisDatabaseConstants.caseLocationsTable} (
      case_id TEXT PRIMARY KEY NOT NULL,
      latitude REAL NOT NULL CHECK(latitude >= -90.0 AND latitude <= 90.0),
      longitude REAL NOT NULL CHECK(longitude >= -180.0 AND longitude <= 180.0),
      source TEXT NOT NULL CHECK(source IN ('EVIDENCE_EXIF', 'MAP_SELECTION', 'SEARCH_RESULT', 'DEVICE_CURRENT_LOCATION')),
      source_evidence_id TEXT,
      place_label TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      FOREIGN KEY(case_id) REFERENCES ${IrisDatabaseConstants.casesTable}(id) ON DELETE CASCADE,
      FOREIGN KEY(source_evidence_id) REFERENCES ${IrisDatabaseConstants.evidenceTable}(id) ON DELETE SET NULL
    )
  ''');
}

Future<void> _createVersionTen(Database database) async {
  await database.execute('''
    CREATE TABLE ${IrisDatabaseConstants.roadContextsTable} (
      case_id TEXT PRIMARY KEY NOT NULL,
      latitude REAL NOT NULL,
      longitude REAL NOT NULL,
      provider TEXT NOT NULL,
      retrieved_at INTEGER NOT NULL,
      status TEXT NOT NULL CHECK(status IN ('AVAILABLE', 'UNAVAILABLE', 'ERROR')),
      roads_json TEXT NOT NULL,
      FOREIGN KEY(case_id) REFERENCES ${IrisDatabaseConstants.casesTable}(id) ON DELETE CASCADE
    )
  ''');
}

Future<void> _createVersionEleven(Database database) async {
  await database.execute('''
    CREATE TABLE ${IrisDatabaseConstants.evidenceWorldAlignmentsTable} (
      evidence_id TEXT PRIMARY KEY NOT NULL,
      case_id TEXT NOT NULL,
      translation_x REAL NOT NULL,
      translation_y REAL NOT NULL,
      translation_z REAL NOT NULL,
      yaw REAL NOT NULL,
      uniform_scale REAL NOT NULL CHECK(uniform_scale > 0.0),
      source TEXT NOT NULL CHECK(source = 'USER_SUPPLIED'),
      geometry_sha256 TEXT NOT NULL CHECK(length(geometry_sha256) = 64),
      road_context_fingerprint TEXT NOT NULL CHECK(length(road_context_fingerprint) = 64),
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      FOREIGN KEY(case_id) REFERENCES ${IrisDatabaseConstants.casesTable}(id) ON DELETE CASCADE,
      FOREIGN KEY(evidence_id) REFERENCES ${IrisDatabaseConstants.evidenceTable}(id) ON DELETE CASCADE
    )
  ''');
}

Future<void> _createVersionSeven(Database database) async {
  await database.execute('''
    CREATE TABLE ${IrisDatabaseConstants.evidenceGeometryAnalysesTable} (
      evidence_id TEXT PRIMARY KEY NOT NULL,
      depth_evidence_sha256 TEXT NOT NULL CHECK(length(depth_evidence_sha256) = 64),
      depth_analyzed_at INTEGER NOT NULL,
      algorithm_version TEXT NOT NULL,
      coordinate_version TEXT NOT NULL,
      projection_mode TEXT NOT NULL CHECK(projection_mode = 'normalized_uncalibrated'),
      scale_status TEXT NOT NULL CHECK(scale_status = 'unresolved'),
      point_count INTEGER NOT NULL CHECK(point_count > 0),
      geometry_file_relative_path TEXT NOT NULL,
      geometry_sha256 TEXT NOT NULL CHECK(length(geometry_sha256) = 64),
      analyzed_at INTEGER NOT NULL,
      FOREIGN KEY(evidence_id) REFERENCES ${IrisDatabaseConstants.evidenceTable}(id) ON DELETE CASCADE
    )
  ''');
}

Future<void> _createVersionSix(Database database) async {
  await database.execute('''
    CREATE TABLE ${IrisDatabaseConstants.evidenceDepthAnalysesTable} (
      evidence_id TEXT PRIMARY KEY NOT NULL,
      model_id TEXT NOT NULL,
      artifact_sha256 TEXT NOT NULL CHECK(length(artifact_sha256) = 64),
      contract_version TEXT NOT NULL,
      source_evidence_sha256 TEXT NOT NULL CHECK(length(source_evidence_sha256) = 64),
      analyzed_at INTEGER NOT NULL,
      status TEXT NOT NULL CHECK(status IN ('complete', 'error')),
      input_width INTEGER NOT NULL,
      input_height INTEGER NOT NULL,
      output_width INTEGER NOT NULL,
      output_height INTEGER NOT NULL,
      depth_min REAL,
      depth_max REAL,
      depth_mean REAL,
      depth_file_relative_path TEXT,
      inference_ms INTEGER,
      FOREIGN KEY(evidence_id) REFERENCES ${IrisDatabaseConstants.evidenceTable}(id) ON DELETE CASCADE
    )
  ''');
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
