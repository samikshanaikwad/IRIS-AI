import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/database/database_constants.dart';
import 'package:iris/core/database/migrations/database_migrations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('v17 to v18 is additive and preserves existing case data', () async {
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(database.close);
    await migrateDatabase(database, 0, 17);
    await database.insert(IrisDatabaseConstants.casesTable, <String, Object?>{
      'id': 'case',
      'title': 'Preserved case',
      'status': 'draft',
      'created_at': 1,
      'updated_at': 1,
    });
    await database
        .insert(IrisDatabaseConstants.evidenceTable, <String, Object?>{
          'id': 'evidence',
          'case_id': 'case',
          'stored_relative_path': 'cases/case/evidence/evidence.jpg',
          'source_type': 'gallery',
          'imported_at': 1,
          'file_size_bytes': 4,
          'sha256': 'a' * 64,
        });
    await database.insert(
      IrisDatabaseConstants.evidenceWorldAlignmentsTable,
      <String, Object?>{
        'evidence_id': 'evidence',
        'case_id': 'case',
        'translation_x': 1.25,
        'translation_y': 0.0,
        'translation_z': -2.5,
        'yaw': 0.4,
        'uniform_scale': 3.0,
        'source': 'USER_SUPPLIED',
        'geometry_sha256': 'b' * 64,
        'road_context_fingerprint': 'c' * 64,
        'world_frame_fingerprint': 'd' * 64,
        'provenance_version': 'iris-world-frame-v1',
        'created_at': 1,
        'updated_at': 1,
      },
    );

    await migrateDatabase(database, 17, 18);

    expect(
      (await database.query(IrisDatabaseConstants.casesTable)).single['title'],
      'Preserved case',
    );
    expect(
      (await database.query(IrisDatabaseConstants.evidenceTable)).single['id'],
      'evidence',
    );
    final alignment = (await database.query(
      IrisDatabaseConstants.evidenceWorldAlignmentsTable,
    )).single;
    expect(alignment['translation_x'], 1.25);
    expect(alignment['translation_z'], -2.5);
    expect(alignment['yaw'], 0.4);
    expect(alignment['uniform_scale'], 3.0);
    expect(alignment['world_frame_fingerprint'], 'd' * 64);
    final tables = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name IN (?, ?)",
      <Object?>[
        IrisDatabaseConstants.evidenceSegmentationAnalysesTable,
        IrisDatabaseConstants.evidenceSegmentationMasksTable,
      ],
    );
    expect(tables, hasLength(2));
    expect(IrisDatabaseConstants.schemaVersion, 19);
  });
}
