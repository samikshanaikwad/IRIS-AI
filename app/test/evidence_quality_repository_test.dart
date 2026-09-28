import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:iris/core/database/database_constants.dart';
import 'package:iris/core/database/iris_database.dart';
import 'package:iris/core/database/migrations/database_migrations.dart';
import 'package:iris/features/classification/data/sqlite_evidence_classification_repository.dart';
import 'package:iris/features/classification/domain/evidence_classification.dart';
import 'package:iris/features/evidence/data/sqlite_evidence_repository.dart';
import 'package:iris/features/evidence_quality/data/sqlite_evidence_quality_repository.dart';
import 'package:iris/features/evidence_quality/domain/evidence_quality_assessment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late Directory directory;
  late IrisDatabase database;
  late SqliteEvidenceQualityRepository qualityRepository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'iris_quality_repository_test_',
    );
    database = IrisDatabase(
      factory: databaseFactoryFfi,
      databasePath: path.join(directory.path, 'quality.db'),
    );
    qualityRepository = SqliteEvidenceQualityRepository(database);
  });

  tearDown(() async {
    await database.close();
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  test(
    'v3 to v7 preserves cases, evidence, quality, and empty analysis tables',
    () async {
      final String databasePath = path.join(directory.path, 'migration.db');
      final Database old = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (Database db, int version) =>
              migrateDatabase(db, 0, version),
        ),
      );
      await _insertCase(old, 'existing-case');
      await _insertEvidence(
        old,
        id: 'existing-evidence',
        caseId: 'existing-case',
      );
      await _insertQuality(old, 'existing-evidence');
      final String originalHash =
          (await old.query(
                IrisDatabaseConstants.evidenceTable,
                columns: <String>['sha256'],
                where: 'id = ?',
                whereArgs: <Object?>['existing-evidence'],
              )).single['sha256']!
              as String;
      await old.close();

      database = IrisDatabase(
        factory: databaseFactoryFfi,
        databasePath: databasePath,
      );
      qualityRepository = SqliteEvidenceQualityRepository(database);
      final Database migrated = await database.open();

      expect(await migrated.getVersion(), 7);
      expect(
        await migrated.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN (?, ?, ?)",
          <Object?>[
            IrisDatabaseConstants.evidenceDetectionAnalysesTable,
            IrisDatabaseConstants.evidenceDetectionsTable,
            IrisDatabaseConstants.evidenceDepthAnalysesTable,
          ],
        ),
        hasLength(3),
      );
      expect(
        await migrated.query(
          IrisDatabaseConstants.casesTable,
          where: 'id = ?',
          whereArgs: <Object?>['existing-case'],
        ),
        hasLength(1),
      );
      final List<Map<String, Object?>> preservedEvidence = await migrated.query(
        IrisDatabaseConstants.evidenceTable,
        where: 'id = ?',
        whereArgs: <Object?>['existing-evidence'],
      );
      expect(preservedEvidence, hasLength(1));
      expect(
        preservedEvidence.single['stored_relative_path'],
        'cases/existing-case/evidence/existing-evidence.png',
      );
      expect(preservedEvidence.single['sha256'], originalHash);
      expect(
        await migrated.query(
          IrisDatabaseConstants.evidenceQualityTable,
          where: 'evidence_id = ?',
          whereArgs: <Object?>['existing-evidence'],
        ),
        hasLength(1),
      );
      expect(
        await migrated.query(IrisDatabaseConstants.evidenceClassificationTable),
        isEmpty,
      );
    },
  );

  test('assessment insert, reload, and reassessment update persist', () async {
    final Database db = await database.open();
    await _insertCase(db, 'case-a');
    await _insertEvidence(db, id: 'evidence-a', caseId: 'case-a');
    final EvidenceQualityAssessment first = _assessment(
      evidenceId: 'evidence-a',
      readiness: EvidenceReadiness.usableWithLimitations,
      sharpness: 72.5,
    );
    await qualityRepository.save(first);

    final EvidenceQualityAssessment loaded = (await qualityRepository
        .getForEvidence('evidence-a'))!;
    expect(loaded.algorithmVersion, 'iris-image-quality-v1');
    expect(loaded.sharpnessValue, 72.5);
    expect(
      loaded.findings.single.code,
      EvidenceQualityFindingCode.possibleBlur,
    );

    final EvidenceQualityAssessment reassessed = _assessment(
      evidenceId: 'evidence-a',
      readiness: EvidenceReadiness.ready,
      sharpness: 184.25,
      findings: const <EvidenceQualityFinding>[],
      assessedAt: DateTime.utc(2026, 9, 28),
    );
    await qualityRepository.save(reassessed);

    final EvidenceQualityAssessment updated = (await qualityRepository
        .getForEvidence('evidence-a'))!;
    expect(updated.readiness, EvidenceReadiness.ready);
    expect(updated.sharpnessValue, 184.25);
    expect(updated.assessedAt, DateTime.utc(2026, 9, 28));
    expect(updated.findings, isEmpty);
    expect(
      await db.query(IrisDatabaseConstants.evidenceQualityTable),
      hasLength(1),
    );
  });

  test('deleting evidence cascades only its assessment', () async {
    final Database db = await database.open();
    await _insertCase(db, 'case-a');
    await _insertEvidence(db, id: 'evidence-a', caseId: 'case-a');
    await _insertEvidence(db, id: 'evidence-b', caseId: 'case-a');
    await qualityRepository.save(_assessment(evidenceId: 'evidence-a'));
    await qualityRepository.save(_assessment(evidenceId: 'evidence-b'));

    expect(
      await SqliteEvidenceRepository(database).delete('evidence-a'),
      isTrue,
    );

    expect(await qualityRepository.getForEvidence('evidence-a'), isNull);
    expect(await qualityRepository.getForEvidence('evidence-b'), isNotNull);
  });

  test(
    'classification persists per evidence and cascades with evidence',
    () async {
      final Database db = await database.open();
      await _insertCase(db, 'case-a');
      await _insertEvidence(db, id: 'evidence-a', caseId: 'case-a');
      final SqliteEvidenceClassificationRepository classifications =
          SqliteEvidenceClassificationRepository(database);
      final EvidenceClassification expected = EvidenceClassification(
        evidenceId: 'evidence-a',
        evidenceSha256: 'a' * 64,
        modelId: 'iris-v0',
        modelTfliteSha256: 'b' * 64,
        modelContractVersion: 'v1',
        rawLogit: 1.25,
        modelScore: 0.777299861,
        threshold: 0.8611480594,
        label: EvidenceClassificationLabel.nonAccident,
        analyzedAt: DateTime.utc(2026, 9, 28),
      );

      await classifications.save(expected);
      final EvidenceClassification loaded = (await classifications
          .getForEvidence('evidence-a'))!;
      expect(loaded.modelScore, closeTo(expected.modelScore, 0.0000001));
      expect(loaded.label, EvidenceClassificationLabel.nonAccident);

      await SqliteEvidenceRepository(database).delete('evidence-a');
      expect(await classifications.getForEvidence('evidence-a'), isNull);
    },
  );

  test(
    'deleting a case cascades assessments and preserves another case',
    () async {
      final Database db = await database.open();
      await _insertCase(db, 'delete-case');
      await _insertCase(db, 'keep-case');
      await _insertEvidence(db, id: 'delete-evidence', caseId: 'delete-case');
      await _insertEvidence(db, id: 'keep-evidence', caseId: 'keep-case');
      await qualityRepository.save(_assessment(evidenceId: 'delete-evidence'));
      await qualityRepository.save(_assessment(evidenceId: 'keep-evidence'));

      await db.delete(
        IrisDatabaseConstants.casesTable,
        where: 'id = ?',
        whereArgs: <Object?>['delete-case'],
      );

      expect(await qualityRepository.getForEvidence('delete-evidence'), isNull);
      expect(
        await qualityRepository.getForEvidence('keep-evidence'),
        isNotNull,
      );
    },
  );
}

Future<void> _insertCase(Database database, String id) async {
  final int timestamp = DateTime.utc(2026, 9, 27).millisecondsSinceEpoch;
  await database.insert(IrisDatabaseConstants.casesTable, <String, Object?>{
    'id': id,
    'title': 'Test fixture: $id',
    'status': 'draft',
    'created_at': timestamp,
    'updated_at': timestamp,
    'incident_occurred_at': null,
    'notes': null,
  });
}

Future<void> _insertEvidence(
  Database database, {
  required String id,
  required String caseId,
}) async {
  final String hashCharacter =
      (id.codeUnits.fold<int>(0, (int sum, int value) => sum + value) % 16)
          .toRadixString(16);
  await database.insert(IrisDatabaseConstants.evidenceTable, <String, Object?>{
    'id': id,
    'case_id': caseId,
    'stored_relative_path': 'cases/$caseId/evidence/$id.png',
    'original_display_name': '$id.png',
    'source_type': 'gallery',
    'captured_at': null,
    'imported_at': DateTime.utc(2026, 9, 27).millisecondsSinceEpoch,
    'mime_type': 'image/png',
    'width_px': 1280,
    'height_px': 720,
    'file_size_bytes': 1024,
    'sha256': hashCharacter * 64,
  });
}

Future<void> _insertQuality(Database database, String evidenceId) async {
  await database
      .insert(IrisDatabaseConstants.evidenceQualityTable, <String, Object?>{
        'evidence_id': evidenceId,
        'assessed_at': DateTime.utc(2026, 9, 27).millisecondsSinceEpoch,
        'algorithm_version': 'iris-image-quality-v1',
        'expected_sha256': 'a' * 64,
        'assessed_sha256': 'a' * 64,
        'file_state': 'available',
        'decode_state': 'decoded',
        'integrity_state': 'verified',
        'readiness_state': 'ready',
        'file_size_bytes': 1024,
        'original_width': 1280,
        'original_height': 720,
        'analysis_width': 1024,
        'analysis_height': 576,
        'orientation': 'landscape',
        'sharpness_value': 120.0,
        'mean_luminance': 128.0,
        'dark_clipped_fraction': 0.0,
        'bright_clipped_fraction': 0.0,
        'findings_json': '[]',
      });
}

EvidenceQualityAssessment _assessment({
  required String evidenceId,
  EvidenceReadiness readiness = EvidenceReadiness.usableWithLimitations,
  double sharpness = 72.5,
  DateTime? assessedAt,
  List<EvidenceQualityFinding>? findings,
}) => EvidenceQualityAssessment(
  evidenceId: evidenceId,
  assessedAt: assessedAt ?? DateTime.utc(2026, 9, 27),
  algorithmVersion: 'iris-image-quality-v1',
  expectedSha256: 'a' * 64,
  assessedSha256: 'a' * 64,
  fileState: EvidenceFileState.available,
  decodeState: EvidenceDecodeState.decoded,
  integrityState: EvidenceIntegrityState.verified,
  readiness: readiness,
  fileSizeBytes: 1024,
  originalWidth: 1280,
  originalHeight: 720,
  analysisWidth: 1024,
  analysisHeight: 576,
  orientation: EvidenceOrientation.landscape,
  sharpnessValue: sharpness,
  meanLuminance: 128,
  darkClippedFraction: 0,
  brightClippedFraction: 0,
  findings:
      findings ??
      const <EvidenceQualityFinding>[
        EvidenceQualityFinding(
          code: EvidenceQualityFindingCode.possibleBlur,
          severity: EvidenceQualitySeverity.warning,
          metric: EvidenceQualityMetric.sharpness,
          measuredValue: 72.5,
          threshold: 100,
          unit: 'Laplacian variance',
          explanation: 'Test fixture finding.',
        ),
      ],
);
