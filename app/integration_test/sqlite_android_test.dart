import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'package:iris/app/iris_app.dart';
import 'package:iris/app/iris_application_services.dart';
import 'package:iris/core/database/database_constants.dart';
import 'package:iris/core/database/iris_database.dart';
import 'package:iris/features/cases/domain/case_repository.dart';
import 'package:iris/features/cases/domain/incident_case.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'MainActivity engine supports production case creation and reopen',
    (WidgetTester tester) async {
      const MethodChannel diagnosticsChannel = MethodChannel(
        'com.iris.debug/plugin_registration',
      );
      final Map<Object?, Object?>? registration = await diagnosticsChannel
          .invokeMapMethod<Object?, Object?>('getRegistrationState');
      expect(
        registration?['activity'],
        'com.iris.incidentreconstruction.MainActivity',
      );
      expect(registration?['generatedRegistrantInvoked'], isTrue);
      expect(registration?['sqfliteClassAvailable'], isTrue);
      expect(registration?['sqfliteRegistered'], isTrue);

      final String databaseDirectory = await getDatabasesPath();
      final String databasePath = path.join(
        databaseDirectory,
        'iris_production_path_test.db',
      );
      await databaseFactory.deleteDatabase(databasePath);

      IrisDatabase database = IrisDatabase(databasePath: databasePath);
      IrisApplicationServices services = IrisApplicationServices.fromDatabase(
        database,
      );
      CaseRepository repository = services.caseRepository;

      addTearDown(() async {
        await services.close();
        await databaseFactory.deleteDatabase(databasePath);
      });

      await tester.pumpWidget(IrisApp(services: services));
      await tester.pumpAndSettle();
      expect(find.text('IRIS'), findsWidgets);

      await tester.tap(
        find.byKey(const ValueKey<String>('analyze-incident-button')),
      );
      await tester.pumpAndSettle();
      const String testTitle = 'Test fixture: Production engine persistence';
      await tester.enterText(
        find.byKey(const ValueKey<String>('case-title-field')),
        testTitle,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('confirm-case-title-button')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Case Overview'), findsOneWidget);
      expect(find.text(testTitle), findsOneWidget);

      final List<IncidentCase> createdCases = await repository.getCases();
      expect(createdCases, hasLength(1));
      expect(createdCases.single.title, testTitle);
      final String createdId = createdCases.single.id;

      final Database opened = await database.open();
      expect(await opened.getVersion(), IrisDatabaseConstants.schemaVersion);
      final List<Map<String, Object?>> tables = await opened.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        <Object?>[IrisDatabaseConstants.casesTable],
      );
      expect(tables, hasLength(1));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await services.close();

      await database.close();
      database = IrisDatabase(databasePath: databasePath);
      services = IrisApplicationServices.fromDatabase(database);
      repository = services.caseRepository;

      final List<IncidentCase> persisted = await repository.getCases();
      expect(persisted, hasLength(1));
      expect(persisted.single.id, createdId);
      expect(persisted.single.title, testTitle);
    },
  );
}
