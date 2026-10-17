import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/database/database_constants.dart';
import 'package:iris/core/database/migrations/database_migrations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'v19 to v20 adds visible surfaces without changing preserved records',
    () async {
      final database = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
      );
      addTearDown(database.close);
      await migrateDatabase(database, 0, 19);
      const hashA =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const hashB =
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
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
            'file_size_bytes': 1,
            'sha256': hashA,
          });
      await database.insert(
        IrisDatabaseConstants.evidenceWorldAlignmentsTable,
        <String, Object?>{
          'evidence_id': 'evidence',
          'case_id': 'case',
          'translation_x': 1.25,
          'translation_y': 0.0,
          'translation_z': -2.5,
          'yaw': .4,
          'uniform_scale': 3.0,
          'source': 'USER_SUPPLIED',
          'geometry_sha256': hashA,
          'road_context_fingerprint': hashB,
          'world_frame_fingerprint': hashA,
          'provenance_version': 'iris-world-frame-v1',
          'created_at': 1,
          'updated_at': 1,
        },
      );
      await database.insert(
        IrisDatabaseConstants.evidenceSegmentationAnalysesTable,
        <String, Object?>{
          'id': 'segmentation',
          'evidence_id': 'evidence',
          'case_id': 'case',
          'source_evidence_sha256': hashA,
          'detection_analysis_id': 'detection',
          'detector_sha256': hashB,
          'detector_contract_version': 'task007-v1',
          'model_id': 'model',
          'model_source_commit': 'source',
          'model_checkpoint_sha256': hashA,
          'encoder_sha256': hashB,
          'decoder_sha256': hashA,
          'coordinate_contract_version': 'iris-image-coordinate-v2',
          'coordinate_metadata_json': '{}',
          'analyzed_at': 1,
          'mask_count': 1,
          'overlay_file_relative_path': 'overlay.png',
          'overlay_sha256': hashB,
        },
      );
      await database.insert(
        IrisDatabaseConstants.evidenceSegmentationMasksTable,
        <String, Object?>{
          'id': 'mask',
          'analysis_id': 'segmentation',
          'detection_index': 0,
          'class_id': 3,
          'class_name': 'motorcycle',
          'detection_score': .9,
          'prompt_left': .1,
          'prompt_top': .1,
          'prompt_right': .9,
          'prompt_bottom': .9,
          'mask_file_relative_path': 'mask.png',
          'mask_sha256': hashA,
          'mask_pixel_count': 1,
        },
      );
      await database.insert(
        IrisDatabaseConstants.scenarioAnalysesTable,
        <String, Object?>{
          'case_id': 'case',
          'engine_version': 'scenario-v1',
          'input_fingerprint': hashA,
          'status': 'INSUFFICIENT_EVIDENCE',
          'hypotheses_json': '[]',
          'generated_at': 1,
        },
      );

      await migrateDatabase(database, 19, 20);

      expect(
        (await database.query(
          IrisDatabaseConstants.casesTable,
        )).single['title'],
        'Preserved case',
      );
      expect(
        (await database.query(
          IrisDatabaseConstants.evidenceSegmentationMasksTable,
        )).single['class_name'],
        'motorcycle',
      );
      expect(
        (await database.query(
          IrisDatabaseConstants.scenarioAnalysesTable,
        )).single['status'],
        'INSUFFICIENT_EVIDENCE',
      );
      final alignment = (await database.query(
        IrisDatabaseConstants.evidenceWorldAlignmentsTable,
      )).single;
      expect(alignment['translation_x'], 1.25);
      expect(alignment['translation_z'], -2.5);
      expect(alignment['yaw'], .4);
      expect(alignment['uniform_scale'], 3.0);
      final tables = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN (?, ?)",
        <Object?>[
          IrisDatabaseConstants.evidencePartialSurfaceAnalysesTable,
          IrisDatabaseConstants.evidencePartialSurfacePartsTable,
        ],
      );
      expect(tables, hasLength(2));
    },
  );
}
