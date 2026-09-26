import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';

import 'package:iris/app/iris_app.dart';
import 'package:iris/app/iris_application_services.dart';
import 'package:iris/core/database/database_constants.dart';
import 'package:iris/core/database/iris_database.dart';
import 'package:iris/features/cases/domain/case_repository.dart';
import 'package:iris/features/cases/domain/incident_case.dart';
import 'package:iris/features/evidence/application/evidence_acquisition_service.dart';
import 'package:iris/features/evidence/data/evidence_storage.dart';
import 'package:iris/features/evidence/domain/evidence_image.dart';

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
      final Map<Object?, Object?> plugins =
          registration?['plugins']! as Map<Object?, Object?>;
      for (final String name in <String>[
        'camera',
        'image_picker',
        'sqflite',
        'jni',
        'jni_flutter',
      ]) {
        final Map<Object?, Object?> state =
            plugins[name]! as Map<Object?, Object?>;
        expect(state['classAvailable'], isTrue, reason: '$name class packaged');
        expect(
          state['registered'],
          isTrue,
          reason: '$name registered on MainActivity engine',
        );
      }

      final String databaseDirectory = await getDatabasesPath();
      final Directory applicationSupport =
          await getApplicationSupportDirectory();
      expect(await applicationSupport.exists(), isTrue);
      final String databasePath = path.join(
        databaseDirectory,
        'iris_production_path_test.db',
      );
      await databaseFactory.deleteDatabase(databasePath);
      final Directory evidenceRoot = Directory(
        path.join(applicationSupport.path, 'iris_task_004_integration_test'),
      );
      if (await evidenceRoot.exists()) {
        await evidenceRoot.delete(recursive: true);
      }
      final EvidenceStorage storage = EvidenceStorage(
        rootProvider: () async => evidenceRoot,
      );

      IrisDatabase database = IrisDatabase(databasePath: databasePath);
      IrisApplicationServices services = IrisApplicationServices.fromDatabase(
        database,
        evidenceStorage: storage,
      );
      CaseRepository repository = services.caseRepository;

      addTearDown(() async {
        await services.close();
        await databaseFactory.deleteDatabase(databasePath);
        if (await evidenceRoot.exists()) {
          await evidenceRoot.delete(recursive: true);
        }
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
      final File sourceImage = File(path.join(evidenceRoot.path, 'source.png'));
      await sourceImage.parent.create(recursive: true);
      await sourceImage.writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Zl4sAAAAASUVORK5CYII=',
        ),
        flush: true,
      );
      final EvidenceImportSummary imported = await services.evidenceAcquisition!
          .importAll(
            caseId: createdId,
            candidates: <EvidenceImportCandidate>[
              EvidenceImportCandidate(
                path: sourceImage.path,
                source: EvidenceSource.gallery,
                originalDisplayName: 'source.png',
                mimeType: 'image/png',
              ),
            ],
          );
      expect(imported.imported, 1);
      final EvidenceImage evidence =
          (await services.evidenceRepository!.getForCase(createdId)).single;
      expect(
        await File(
          await storage.absolutePath(evidence.storedRelativePath),
        ).exists(),
        isTrue,
      );

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
      services = IrisApplicationServices.fromDatabase(
        database,
        evidenceStorage: storage,
      );
      repository = services.caseRepository;

      final List<IncidentCase> persisted = await repository.getCases();
      expect(persisted, hasLength(1));
      expect(persisted.single.id, createdId);
      expect(persisted.single.title, testTitle);
      expect(
        await services.evidenceRepository!.getForCase(createdId),
        hasLength(1),
      );
    },
  );
}
