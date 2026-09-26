import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'package:iris/core/database/database_constants.dart';
import 'package:iris/core/database/iris_database.dart';
import 'package:iris/features/cases/data/sqlite_case_repository.dart';
import 'package:iris/features/cases/domain/incident_case.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Android SQLite creates schema and inserts before and after reopen',
    (WidgetTester tester) async {
      final String databasePath = path.join(
        await getDatabasesPath(),
        'iris_android_integration_test.db',
      );
      await databaseFactory.deleteDatabase(databasePath);

      IrisDatabase database = IrisDatabase(databasePath: databasePath);
      int clockTick = 0;
      DateTime clock() =>
          DateTime.utc(2026, 1, 1).add(Duration(seconds: clockTick++));
      addTearDown(() async {
        await database.close();
        await databaseFactory.deleteDatabase(databasePath);
      });

      SqliteCaseRepository repository = SqliteCaseRepository(
        database,
        clock: clock,
      );
      final IncidentCase first = await repository.createCase(
        title: 'Test fixture: Android fresh insert',
      );
      expect(first.title, 'Test fixture: Android fresh insert');

      final Database opened = await database.open();
      expect(await opened.getVersion(), IrisDatabaseConstants.schemaVersion);
      final List<Map<String, Object?>> tables = await opened.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        <Object?>[IrisDatabaseConstants.casesTable],
      );
      expect(tables, hasLength(1));

      await database.close();
      database = IrisDatabase(databasePath: databasePath);
      repository = SqliteCaseRepository(database, clock: clock);
      final IncidentCase second = await repository.createCase(
        title: 'Test fixture: Android reopen insert',
      );

      final List<IncidentCase> persisted = await repository.getCases();
      expect(persisted.map((IncidentCase item) => item.id), <String>[
        second.id,
        first.id,
      ]);
    },
  );
}
