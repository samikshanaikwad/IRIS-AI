import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/database/database_constants.dart';
import 'package:iris/core/database/migrations/database_migrations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test(
    'v15 to v16 preserves legacy alignment and adds nullable provenance',
    () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await migrateDatabase(db, 0, 15);
      await db.insert(IrisDatabaseConstants.casesTable, {
        'id': 'case',
        'title': 'Case',
        'status': 'draft',
        'created_at': 1,
        'updated_at': 1,
      });
      await db.insert(IrisDatabaseConstants.evidenceTable, {
        'id': 'evidence',
        'case_id': 'case',
        'stored_relative_path': 'fixture.jpg',
        'source_type': 'gallery',
        'imported_at': 1,
        'file_size_bytes': 1,
        'sha256': 'a' * 64,
      });
      await db.insert(IrisDatabaseConstants.evidenceWorldAlignmentsTable, {
        'evidence_id': 'evidence',
        'case_id': 'case',
        'translation_x': 1.25,
        'translation_y': 2.5,
        'translation_z': 3.75,
        'yaw': .5,
        'uniform_scale': 4.0,
        'source': 'USER_SUPPLIED',
        'geometry_sha256': 'b' * 64,
        'road_context_fingerprint': 'c' * 64,
        'created_at': 1,
        'updated_at': 2,
      });

      await migrateDatabase(db, 15, 16);
      // The migration is intentionally idempotent for interrupted upgrades.
      await migrateDatabase(db, 15, 16);

      final row = (await db.query(
        IrisDatabaseConstants.evidenceWorldAlignmentsTable,
      )).single;
      expect(row['translation_x'], 1.25);
      expect(row['translation_y'], 2.5);
      expect(row['translation_z'], 3.75);
      expect(row['yaw'], .5);
      expect(row['uniform_scale'], 4.0);
      expect(row['geometry_sha256'], 'b' * 64);
      expect(row['road_context_fingerprint'], 'c' * 64);
      expect(row['world_frame_fingerprint'], isNull);
      expect(row['provenance_version'], isNull);
      expect(IrisDatabaseConstants.schemaVersion, 18);
    },
  );
}
