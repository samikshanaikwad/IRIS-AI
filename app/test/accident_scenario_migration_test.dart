import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/database/database_constants.dart';
import 'package:iris/core/database/migrations/database_migrations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  test(
    'v18 to v19 is additive and preserves case evidence and alignment',
    () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await migrateDatabase(db, 0, 18);
      await db.insert(IrisDatabaseConstants.casesTable, {
        'id': 'case-1',
        'title': 'Existing',
        'status': 'draft',
        'created_at': 1,
        'updated_at': 1,
      });
      await db.insert(IrisDatabaseConstants.evidenceTable, {
        'id': 'e1',
        'case_id': 'case-1',
        'stored_relative_path': 'e1.jpg',
        'source_type': 'gallery',
        'imported_at': 1,
        'file_size_bytes': 1,
        'sha256': 'a' * 64,
      });
      await db.insert(IrisDatabaseConstants.evidenceWorldAlignmentsTable, {
        'evidence_id': 'e1',
        'case_id': 'case-1',
        'translation_x': 1.0,
        'translation_y': 0.0,
        'translation_z': 2.0,
        'yaw': .3,
        'uniform_scale': 1.2,
        'source': 'USER_SUPPLIED',
        'geometry_sha256': 'b' * 64,
        'road_context_fingerprint': 'c' * 64,
        'created_at': 1,
        'updated_at': 1,
      });
      await migrateDatabase(db, 18, 19);
      expect((await db.query(IrisDatabaseConstants.casesTable)).length, 1);
      expect((await db.query(IrisDatabaseConstants.evidenceTable)).length, 1);
      final alignment = (await db.query(
        IrisDatabaseConstants.evidenceWorldAlignmentsTable,
      )).single;
      expect(alignment['translation_x'], 1.0);
      expect(alignment['yaw'], .3);
      expect(
        (await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE name = 'scenario_observations'",
        )).length,
        1,
      );
      await db.close();
    },
  );
}
