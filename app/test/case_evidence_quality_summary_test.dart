import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'package:iris/app/iris_app.dart';
import 'package:iris/features/cases/domain/incident_case.dart';
import 'package:iris/features/evidence/application/evidence_acquisition_service.dart';
import 'package:iris/features/evidence/domain/evidence_image.dart';

import 'support/case_test_harness.dart';
import 'support/widget_test_tools.dart';

void main() {
  late CaseTestHarness harness;

  setUp(() async {
    harness = await CaseTestHarness.create();
  });

  tearDown(() => harness.dispose());

  testWidgets('existing evidence is truthfully shown as not assessed', (
    WidgetTester tester,
  ) async {
    final IncidentCase
    incidentCase = await runOutsideFakeAsync(tester, () async {
      final IncidentCase value = await harness.repository.createCase(
        title: 'Test fixture: Quality summary',
      );
      final File source =
          await File(
            path.join(harness.directory.path, 'source.png'),
          ).writeAsBytes(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Zl4sAAAAASUVORK5CYII=',
            ),
            flush: true,
          );
      final EvidenceImportSummary importResult = await harness
          .services
          .evidenceAcquisition!
          .importAll(
            caseId: value.id,
            candidates: <EvidenceImportCandidate>[
              EvidenceImportCandidate(
                path: source.path,
                source: EvidenceSource.gallery,
                originalDisplayName: 'source.png',
                mimeType: 'image/png',
              ),
            ],
          );
      expect(importResult.imported, 1);
      return value;
    });

    await tester.pumpWidget(IrisApp(services: harness.services));
    await pumpUntilStorageStateSettles(tester);
    await tester.tap(find.byKey(const ValueKey<String>('nav-cases')));
    await pumpUiTransition(tester);
    await tester.tap(
      find.byKey(ValueKey<String>('cases-case-${incidentCase.id}')),
    );
    await pumpUntilFound(tester, find.text('Not assessed'));

    expect(find.text('Not assessed'), findsOneWidget);
    expect(
      find.textContaining('1 stored image · 1 not assessed'),
      findsOneWidget,
    );
    expect(find.textContaining('Need at least 2 images'), findsNothing);
  });
}
