import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:iris/core/database/database_constants.dart';
import 'package:iris/core/database/iris_database.dart';
import 'package:iris/features/cases/data/sqlite_case_repository.dart';
import 'package:iris/features/cases/domain/case_status.dart';
import 'package:iris/features/cases/domain/case_title_validator.dart';
import 'package:iris/features/cases/domain/incident_case.dart';

void main() {
  late Directory directory;
  late String databasePath;
  late IrisDatabase database;
  late SqliteCaseRepository repository;
  late int clockTick;

  DateTime clock() {
    final DateTime value = DateTime.utc(
      2026,
      1,
      1,
    ).add(Duration(minutes: clockTick));
    clockTick++;
    return value;
  }

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('iris_repository_test_');
    databasePath = path.join(directory.path, 'repository.db');
    database = IrisDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    clockTick = 0;
    repository = SqliteCaseRepository(database, clock: clock);
  });

  tearDown(() async {
    await database.close();
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  test('database initializes with explicit version and cases schema', () async {
    final Database db = await database.open();

    expect(await db.getVersion(), IrisDatabaseConstants.schemaVersion);
    final List<Map<String, Object?>> tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      <Object?>[IrisDatabaseConstants.casesTable],
    );
    expect(tables, hasLength(1));

    final List<Map<String, Object?>> columns = await db.rawQuery(
      'PRAGMA table_info(${IrisDatabaseConstants.casesTable})',
    );
    expect(
      columns.map((Map<String, Object?> row) => row['name']).toList(),
      <Object?>[
        'id',
        'title',
        'status',
        'created_at',
        'updated_at',
        'incident_occurred_at',
        'notes',
      ],
    );
  });

  test(
    'database path uses the Android-compatible database directory',
    () async {
      final String androidDirectory = path.join(
        'data',
        'user',
        '0',
        'com.iris.incidentreconstruction',
        'databases',
      );
      final IrisDatabase pathDatabase = IrisDatabase(
        factory: databaseFactoryFfi,
        databaseDirectoryProvider: () async => androidDirectory,
      );

      expect(
        await pathDatabase.resolvePath(),
        path.join(androidDirectory, IrisDatabaseConstants.fileName),
      );
    },
  );

  test('clean database returns zero cases', () async {
    expect(await repository.getCases(), isEmpty);
  });

  test('creating a case persists real fields and Draft status', () async {
    final IncidentCase created = await repository.createCase(
      title: '  User-entered incident title  ',
    );

    expect(created.title, 'User-entered incident title');
    expect(created.status, CaseStatus.draft);
    expect(created.createdAt, DateTime.utc(2026, 1, 1));
    expect(created.updatedAt, created.createdAt);
    expect(created.incidentOccurredAt, isNull);
    expect(created.notes, isNull);
    expect(
      created.id,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );

    final IncidentCase? persisted = await repository.getCaseById(created.id);
    expect(persisted?.title, created.title);
    expect(persisted?.createdAt, created.createdAt);
    expect(persisted?.updatedAt, created.updatedAt);
  });

  test('generated identifiers are unique', () async {
    final IncidentCase first = await repository.createCase(title: 'First');
    final IncidentCase second = await repository.createCase(title: 'Second');

    expect(first.id, isNot(second.id));
  });

  test('missing case lookup returns null', () async {
    expect(await repository.getCaseById('not-present'), isNull);
  });

  test('cases list by most recently updated first', () async {
    final IncidentCase first = await repository.createCase(title: 'First');
    final IncidentCase second = await repository.createCase(title: 'Second');
    await repository.renameCase(id: first.id, title: 'First renamed');

    final List<IncidentCase> cases = await repository.getCases();
    expect(cases.map((IncidentCase value) => value.id), <String>[
      first.id,
      second.id,
    ]);
    expect((await repository.getCases(limit: 1)).single.id, first.id);
  });

  test('rename safely persists punctuation and changes updatedAt', () async {
    final IncidentCase created = await repository.createCase(title: 'Original');
    final IncidentCase renamed = await repository.renameCase(
      id: created.id,
      title: " Driver's observation – northbound ",
    );

    expect(renamed.title, "Driver's observation – northbound");
    expect(renamed.updatedAt, isNot(created.updatedAt));
    expect((await repository.getCaseById(created.id))?.title, renamed.title);
  });

  test('deleting one case preserves another case', () async {
    final IncidentCase first = await repository.createCase(title: 'First');
    final IncidentCase second = await repository.createCase(title: 'Second');

    expect(await repository.deleteCase(first.id), isTrue);
    expect(await repository.deleteCase(first.id), isFalse);
    expect(await repository.getCaseById(first.id), isNull);
    expect((await repository.getCaseById(second.id))?.id, second.id);
  });

  test('invalid titles are rejected before persistence', () async {
    await expectLater(
      repository.createCase(title: '   \n  '),
      throwsA(isA<CaseValidationException>()),
    );
    await expectLater(
      repository.createCase(title: List<String>.filled(121, 'a').join()),
      throwsA(isA<CaseValidationException>()),
    );
    expect(await repository.getCases(), isEmpty);
  });

  test('unknown future status is handled defensively', () async {
    final Database db = await database.open();
    final int timestamp = DateTime.utc(2026, 1, 1).millisecondsSinceEpoch;
    await db.insert(IrisDatabaseConstants.casesTable, <String, Object?>{
      'id': 'test-future-status',
      'title': 'Controlled test title',
      'status': 'future_status',
      'created_at': timestamp,
      'updated_at': timestamp,
      'incident_occurred_at': null,
      'notes': null,
    });

    expect(
      (await repository.getCaseById('test-future-status'))?.status,
      CaseStatus.unknown,
    );
  });

  test('reopening the same database retains a case', () async {
    final IncidentCase created = await repository.createCase(
      title: 'Persistence test title',
    );
    await database.close();

    final IrisDatabase reopenedDatabase = IrisDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    final SqliteCaseRepository reopenedRepository = SqliteCaseRepository(
      reopenedDatabase,
    );
    addTearDown(reopenedDatabase.close);

    expect(
      (await reopenedRepository.getCaseById(created.id))?.title,
      created.title,
    );
  });

  test(
    'close and reopen supports another insert at current schema version',
    () async {
      final IncidentCase first = await repository.createCase(
        title: 'Test fixture: Before close',
      );
      await database.close();

      database = IrisDatabase(
        factory: databaseFactoryFfi,
        databasePath: databasePath,
      );
      repository = SqliteCaseRepository(database, clock: clock);
      final IncidentCase second = await repository.createCase(
        title: 'Test fixture: After reopen',
      );

      final List<IncidentCase> cases = await repository.getCases();
      expect(cases.map((IncidentCase item) => item.id), <String>[
        second.id,
        first.id,
      ]);
      expect(
        await (await database.open()).getVersion(),
        IrisDatabaseConstants.schemaVersion,
      );
    },
  );

  test(
    'version 1 database missing cases table fails without deletion',
    () async {
      final Database inconsistent = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(version: 1),
      );
      await inconsistent.close();

      await expectLater(database.open(), throwsA(isA<StateError>()));

      final Database unchanged = await databaseFactoryFfi.openDatabase(
        databasePath,
      );
      expect(await unchanged.getVersion(), 1);
      expect(
        await unchanged.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
          <Object?>[IrisDatabaseConstants.casesTable],
        ),
        isEmpty,
      );
      await unchanged.close();
    },
  );
}
