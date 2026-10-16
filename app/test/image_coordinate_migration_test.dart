import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/database/database_constants.dart';
import 'package:iris/core/database/migrations/database_migrations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test(
    'v16 to v17 preserves analyses and adds nullable coordinate metadata',
    () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await migrateDatabase(db, 0, 16);
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
      await db.insert(IrisDatabaseConstants.evidenceDetectionAnalysesTable, {
        'id': 'detection',
        'evidence_id': 'evidence',
        'evidence_sha256': 'a' * 64,
        'detector_id': 'detector',
        'detector_sha256': 'b' * 64,
        'contract_version': 'legacy',
        'status': 'complete',
        'analyzed_at': 1,
      });
      await db.insert(IrisDatabaseConstants.evidenceDepthAnalysesTable, {
        'evidence_id': 'evidence',
        'model_id': 'depth',
        'artifact_sha256': 'c' * 64,
        'contract_version': 'legacy',
        'source_evidence_sha256': 'a' * 64,
        'analyzed_at': 1,
        'status': 'complete',
        'input_width': 4,
        'input_height': 3,
        'output_width': 2,
        'output_height': 2,
      });

      await migrateDatabase(db, 16, 17);
      await migrateDatabase(db, 16, 17);

      final detection = (await db.query(
        IrisDatabaseConstants.evidenceDetectionAnalysesTable,
      )).single;
      final depth = (await db.query(
        IrisDatabaseConstants.evidenceDepthAnalysesTable,
      )).single;
      expect(detection['contract_version'], 'legacy');
      expect(detection['coordinate_contract_version'], isNull);
      expect(detection['coordinate_metadata_json'], isNull);
      expect(depth['contract_version'], 'legacy');
      expect(depth['coordinate_contract_version'], isNull);
      expect(depth['coordinate_metadata_json'], isNull);
      expect(IrisDatabaseConstants.schemaVersion, 18);
    },
  );
}
