import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:iris/app/iris_application_services.dart';
import 'package:iris/core/database/database_constants.dart';
import 'package:iris/core/database/iris_database.dart';
import 'package:iris/core/database/migrations/database_migrations.dart';
import 'package:iris/features/evidence/application/evidence_acquisition_service.dart';
import 'package:iris/features/evidence/data/evidence_storage.dart';
import 'package:iris/features/evidence/domain/evidence_image.dart';
import 'package:iris/features/evidence/domain/evidence_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late Directory directory;
  late IrisDatabase database;
  late EvidenceStorage storage;
  late IrisApplicationServices services;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('iris_evidence_test_');
    database = IrisDatabase(
      factory: databaseFactoryFfi,
      databasePath: path.join(directory.path, 'evidence.db'),
    );
    storage = EvidenceStorage(
      rootProvider: () async => Directory(path.join(directory.path, 'files')),
    );
    services = IrisApplicationServices.fromDatabase(
      database,
      evidenceStorage: storage,
    );
  });

  tearDown(() async {
    await services.close();
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  test(
    'fresh schema contains evidence table, index, and foreign key',
    () async {
      final db = await database.open();
      expect(await db.getVersion(), IrisDatabaseConstants.schemaVersion);
      expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
          <Object?>[IrisDatabaseConstants.evidenceTable],
        ),
        hasLength(1),
      );
      expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'index' AND name = ?",
          <Object?>[IrisDatabaseConstants.evidenceCaseIndex],
        ),
        hasLength(1),
      );
      final List<Map<String, Object?>> keys = await db.rawQuery(
        'PRAGMA foreign_key_list(${IrisDatabaseConstants.evidenceTable})',
      );
      expect(keys.single['table'], IrisDatabaseConstants.casesTable);
      expect(keys.single['on_delete'], 'CASCADE');
    },
  );

  test(
    'version 1 migration preserves existing case and creates current schema',
    () async {
      await services.close();
      final String databasePath = path.join(directory.path, 'migration.db');
      final old = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) => migrateDatabase(db, 0, version),
        ),
      );
      final int timestamp = DateTime.utc(2026).millisecondsSinceEpoch;
      await old.insert(IrisDatabaseConstants.casesTable, <String, Object?>{
        'id': 'migration-case',
        'title': 'Test fixture: Existing case',
        'status': 'draft',
        'created_at': timestamp,
        'updated_at': timestamp,
        'incident_occurred_at': null,
        'notes': null,
      });
      await old.close();

      database = IrisDatabase(
        factory: databaseFactoryFfi,
        databasePath: databasePath,
      );
      services = IrisApplicationServices.fromDatabase(
        database,
        evidenceStorage: storage,
      );
      expect(
        (await services.caseRepository.getCases()).single.id,
        'migration-case',
      );
      expect(
        await (await database.open()).getVersion(),
        IrisDatabaseConstants.schemaVersion,
      );
    },
  );

  test(
    'v13 to v14 preserves persisted environment context and adds provider state',
    () async {
      await services.close();
      final databasePath = path.join(directory.path, 'environment-v13.db');
      final v13 = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 13,
          onCreate: (db, version) => migrateDatabase(db, 0, version),
        ),
      );
      final timestamp = DateTime.utc(2026).millisecondsSinceEpoch;
      await v13.insert(IrisDatabaseConstants.casesTable, {
        'id': 'environment-case',
        'title': 'Existing environment case',
        'status': 'draft',
        'created_at': timestamp,
        'updated_at': timestamp,
      });
      await v13.insert(IrisDatabaseConstants.environmentContextsTable, {
        'case_id': 'environment-case',
        'latitude': 12.0,
        'longitude': 77.0,
        'provider': 'OpenStreetMap Overpass API',
        'retrieved_at': timestamp,
        'status': 'EMPTY',
        'features_json': '[]',
      });
      await v13.close();

      database = IrisDatabase(
        factory: databaseFactoryFfi,
        databasePath: databasePath,
      );
      services = IrisApplicationServices.fromDatabase(
        database,
        evidenceStorage: storage,
      );
      final migrated = await database.open();
      final row = (await migrated.query(
        IrisDatabaseConstants.environmentContextsTable,
        where: 'case_id = ?',
        whereArgs: ['environment-case'],
      )).single;
      expect(await migrated.getVersion(), 14);
      expect(row['latitude'], 12.0);
      expect(row['longitude'], 77.0);
      expect(row['features_json'], '[]');
      expect(row['provider_state'], 'UNKNOWN');
    },
  );

  test(
    'single and multiple imports preserve bytes, hash, and persistence',
    () async {
      final firstCase = await services.caseRepository.createCase(
        title: 'Test fixture: Evidence case',
      );
      final File first = await _writeImage(directory, 'first.png');
      final File second = await _writeImage(
        directory,
        'second.png',
        alternate: true,
      );

      final EvidenceImportSummary summary = await services.evidenceAcquisition!
          .importAll(
            caseId: firstCase.id,
            candidates: <EvidenceImportCandidate>[
              _candidate(first),
              _candidate(second),
            ],
          );
      expect(summary.imported, 2);
      expect(summary.failed, 0);
      final items = await services.evidenceRepository!.getForCase(firstCase.id);
      expect(items, hasLength(2));
      for (final EvidenceImage item in items) {
        final File managed = File(
          await storage.absolutePath(item.storedRelativePath),
        );
        expect(await managed.exists(), isTrue);
        final File original = item.originalDisplayName == 'first.png'
            ? first
            : second;
        expect(await managed.readAsBytes(), await original.readAsBytes());
        expect(
          item.sha256,
          sha256.convert(await managed.readAsBytes()).toString(),
        );
      }

      await services.close();
      services = IrisApplicationServices.fromDatabase(
        database,
        evidenceStorage: storage,
      );
      expect(
        await services.evidenceRepository!.getForCase(firstCase.id),
        hasLength(2),
      );
    },
  );

  test(
    'same-case duplicate is skipped while another case may import it',
    () async {
      final firstCase = await services.caseRepository.createCase(
        title: 'First case',
      );
      final secondCase = await services.caseRepository.createCase(
        title: 'Second case',
      );
      final File image = await _writeImage(directory, 'duplicate.png');
      final EvidenceImportCandidate candidate = _candidate(image);

      expect(
        (await services.evidenceAcquisition!.importAll(
          caseId: firstCase.id,
          candidates: <EvidenceImportCandidate>[candidate, candidate],
        )).results.map((item) => item.status),
        <EvidenceImportStatus>[
          EvidenceImportStatus.imported,
          EvidenceImportStatus.duplicate,
        ],
      );
      expect(
        (await services.evidenceAcquisition!.importAll(
          caseId: secondCase.id,
          candidates: <EvidenceImportCandidate>[candidate],
        )).imported,
        1,
      );
    },
  );

  test('one failed batch item does not remove a successful import', () async {
    final incidentCase = await services.caseRepository.createCase(
      title: 'Batch case',
    );
    final File image = await _writeImage(directory, 'available.png');
    final EvidenceImportSummary summary = await services.evidenceAcquisition!
        .importAll(
          caseId: incidentCase.id,
          candidates: <EvidenceImportCandidate>[
            _candidate(image),
            const EvidenceImportCandidate(
              path: 'missing-test-image.png',
              source: EvidenceSource.gallery,
            ),
          ],
        );
    expect(summary.imported, 1);
    expect(summary.failed, 1);
    expect(
      await services.evidenceRepository!.getForCase(incidentCase.id),
      hasLength(1),
    );
  });

  test('database failure removes the copied managed file', () async {
    final Directory isolatedRoot = Directory(
      path.join(directory.path, 'failure-files'),
    );
    final EvidenceStorage isolatedStorage = EvidenceStorage(
      rootProvider: () async => isolatedRoot,
    );
    final EvidenceAcquisitionService acquisition = EvidenceAcquisitionService(
      repository: _FailingEvidenceRepository(),
      storage: isolatedStorage,
      idFactory: () => 'controlled-evidence-id',
    );
    final File image = await _writeImage(directory, 'database-failure.png');

    final EvidenceImportSummary summary = await acquisition.importAll(
      caseId: 'controlled-case-id',
      candidates: <EvidenceImportCandidate>[_candidate(image)],
    );

    expect(summary.failed, 1);
    final List<FileSystemEntity> remaining = await isolatedRoot.exists()
        ? await isolatedRoot
              .list(recursive: true)
              .where((entity) => entity is File)
              .toList()
        : <FileSystemEntity>[];
    expect(remaining, isEmpty);
  });

  test('empty picker result performs no import', () async {
    final EvidenceImportSummary summary = await services.evidenceAcquisition!
        .importAll(
          caseId: 'not-used',
          candidates: const <EvidenceImportCandidate>[],
        );
    expect(summary.results, isEmpty);
  });

  test('evidence deletion removes managed file and row', () async {
    final incidentCase = await services.caseRepository.createCase(
      title: 'Delete image',
    );
    final File image = await _writeImage(directory, 'delete.png');
    await services.evidenceAcquisition!.importAll(
      caseId: incidentCase.id,
      candidates: <EvidenceImportCandidate>[_candidate(image)],
    );
    final EvidenceImage evidence =
        (await services.evidenceRepository!.getForCase(incidentCase.id)).single;
    final String managedPath = await storage.absolutePath(
      evidence.storedRelativePath,
    );
    final controller = services.evidenceControllerFor(incidentCase.id);
    expect(await controller.delete(evidence), isTrue);
    expect(await File(managedPath).exists(), isFalse);
    expect(
      await services.evidenceRepository!.getForCase(incidentCase.id),
      isEmpty,
    );
    controller.dispose();
  });

  test(
    'case deletion cascades rows/files and preserves another case',
    () async {
      final firstCase = await services.caseRepository.createCase(
        title: 'Delete case',
      );
      final secondCase = await services.caseRepository.createCase(
        title: 'Keep case',
      );
      final File image = await _writeImage(directory, 'case-delete.png');
      for (final caseValue in <String>[firstCase.id, secondCase.id]) {
        await services.evidenceAcquisition!.importAll(
          caseId: caseValue,
          candidates: <EvidenceImportCandidate>[_candidate(image)],
        );
      }

      expect(await services.caseRepository.deleteCase(firstCase.id), isTrue);
      expect(
        await services.evidenceRepository!.getForCase(firstCase.id),
        isEmpty,
      );
      expect(
        await services.evidenceRepository!.getForCase(secondCase.id),
        hasLength(1),
      );
      expect(
        await services.caseRepository.getCaseById(secondCase.id),
        isNotNull,
      );
    },
  );

  test(
    'managed storage rejects unsafe identifiers and traversal paths',
    () async {
      expect(
        () => storage.relativeEvidencePath(
          caseId: '../outside',
          evidenceId: 'safe',
          sourcePath: 'image.jpg',
        ),
        throwsArgumentError,
      );
      await expectLater(
        storage.absolutePath('../outside.jpg'),
        throwsArgumentError,
      );
    },
  );
}

class _FailingEvidenceRepository implements EvidenceRepository {
  @override
  Future<EvidenceImage> add(EvidenceImage evidence) =>
      Future<EvidenceImage>.error(
        StateError('Controlled test database failure.'),
      );

  @override
  Future<bool> delete(String id) async => false;

  @override
  Future<EvidenceImage?> findDuplicate({
    required String caseId,
    required String sha256,
  }) async => null;

  @override
  Future<EvidenceImage?> getById(String id) async => null;

  @override
  Future<List<EvidenceImage>> getForCase(String caseId) async =>
      const <EvidenceImage>[];
}

EvidenceImportCandidate _candidate(File file) => EvidenceImportCandidate(
  path: file.path,
  source: EvidenceSource.gallery,
  originalDisplayName: path.basename(file.path),
  mimeType: 'image/png',
);

Future<File> _writeImage(
  Directory directory,
  String name, {
  bool alternate = false,
}) async {
  final String base64Image = alternate
      ? 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='
      : 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Zl4sAAAAASUVORK5CYII=';
  return File(
    path.join(directory.path, name),
  ).writeAsBytes(base64Decode(base64Image), flush: true);
}
