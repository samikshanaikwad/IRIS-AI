import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:iris/app/iris_app.dart';
import 'package:iris/app/iris_application_services.dart';
import 'package:iris/features/cases/domain/case_repository.dart';
import 'package:iris/features/cases/domain/incident_case.dart';

import 'support/case_test_harness.dart';
import 'support/widget_test_tools.dart';

void main() {
  late CaseTestHarness harness;

  setUp(() async {
    harness = await CaseTestHarness.create();
  });

  tearDown(() async {
    await harness.dispose();
  });

  Future<void> pumpIris(WidgetTester tester) async {
    await tester.pumpWidget(IrisApp(services: harness.services));
    await pumpUntilStorageStateSettles(tester);
  }

  Future<void> createCaseThroughUi(WidgetTester tester, String title) async {
    final Finder action = find.byKey(
      const ValueKey<String>('analyze-incident-button'),
    );
    await tester.ensureVisible(action);
    await tester.tap(action);
    await pumpUiTransition(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('case-title-field')),
      title,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('confirm-case-title-button')),
    );
    await pumpUntilFound(
      tester,
      find.text('Case Overview'),
      failureMessage: 'Created case did not open its overview.',
    );
  }

  Future<void> openCaseFromCases(
    WidgetTester tester,
    IncidentCase incidentCase,
  ) async {
    await tester.tap(find.byKey(const ValueKey<String>('nav-cases')));
    await pumpUiTransition(tester);
    await tester.tap(
      find.byKey(ValueKey<String>('cases-case-${incidentCase.id}')),
    );
    await pumpUntilFound(
      tester,
      find.text('Case Overview'),
      failureMessage: 'Persisted case did not open its overview.',
    );
  }

  testWidgets('UI creation persists and opens actual Case Overview', (
    WidgetTester tester,
  ) async {
    await pumpIris(tester);
    const String title = 'Test fixture: North entry incident';

    await createCaseThroughUi(tester, title);

    final List<IncidentCase> persisted = await runOutsideFakeAsync(
      tester,
      harness.repository.getCases,
    );
    expect(persisted, hasLength(1));
    expect(persisted.single.title, title);
    expect(find.text('Case Overview'), findsOneWidget);
    expect(find.text(title), findsOneWidget);
    expect(find.text('Draft'), findsOneWidget);
    expect(find.text('No evidence added'), findsOneWidget);

    await tester.pageBack();
    await pumpUiTransition(tester);
    await tester.scrollUntilVisible(
      find.byKey(ValueKey<String>('home-case-${persisted.single.id}')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(ValueKey<String>('home-case-${persisted.single.id}')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('nav-cases')));
    await pumpUiTransition(tester);
    expect(
      find.byKey(ValueKey<String>('cases-case-${persisted.single.id}')),
      findsOneWidget,
    );
  });

  testWidgets('tapping a persisted case opens the matching case ID', (
    WidgetTester tester,
  ) async {
    final IncidentCase first = await runOutsideFakeAsync(
      tester,
      () => harness.repository.createCase(title: 'Test fixture: First case'),
    );
    final IncidentCase second = await runOutsideFakeAsync(
      tester,
      () => harness.repository.createCase(title: 'Test fixture: Second case'),
    );
    await pumpIris(tester);

    await openCaseFromCases(tester, first);

    expect(find.text(first.title), findsOneWidget);
    expect(find.text(second.title), findsNothing);
  });

  testWidgets('rename persists and immediately updates Overview', (
    WidgetTester tester,
  ) async {
    final IncidentCase incidentCase = await runOutsideFakeAsync(
      tester,
      () =>
          harness.repository.createCase(title: 'Test fixture: Original title'),
    );
    await pumpIris(tester);
    await openCaseFromCases(tester, incidentCase);

    await tester.tap(find.byKey(const ValueKey<String>('rename-case-button')));
    await pumpUiTransition(tester);
    const String renamedTitle = 'Test fixture: Renamed title';
    await tester.enterText(
      find.byKey(const ValueKey<String>('case-title-field')),
      renamedTitle,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('confirm-case-title-button')),
    );
    await pumpUntilFound(
      tester,
      find.text(renamedTitle),
      failureMessage: 'Renamed title did not appear.',
    );

    expect(find.text(renamedTitle), findsOneWidget);
    final List<IncidentCase> renamedCases = await runOutsideFakeAsync(
      tester,
      harness.repository.getCases,
    );
    expect(renamedCases.single.title, renamedTitle);
  });

  testWidgets(
    'delete cancellation preserves case and confirmation removes it',
    (WidgetTester tester) async {
      final IncidentCase incidentCase = await runOutsideFakeAsync(
        tester,
        () => harness.repository.createCase(
          title: 'Test fixture: Delete lifecycle',
        ),
      );
      await pumpIris(tester);
      await openCaseFromCases(tester, incidentCase);

      await tester.tap(
        find.byKey(const ValueKey<String>('delete-case-button')),
      );
      await pumpUiTransition(tester);
      expect(find.textContaining(incidentCase.title), findsWidgets);
      await tester.tap(
        find.byKey(const ValueKey<String>('cancel-delete-button')),
      );
      await pumpUiTransition(tester);
      final List<IncidentCase> afterCancellation = await runOutsideFakeAsync(
        tester,
        harness.repository.getCases,
      );
      expect(
        afterCancellation.map((IncidentCase item) => item.id),
        contains(incidentCase.id),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('delete-case-button')),
      );
      await pumpUiTransition(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('confirm-delete-button')),
      );
      await pumpUntilFound(
        tester,
        find.text('No incident cases'),
        failureMessage: 'Confirmed deletion did not update the Cases screen.',
      );

      expect(
        await runOutsideFakeAsync(tester, harness.repository.getCases),
        isEmpty,
      );
      expect(find.text('No incident cases'), findsOneWidget);
    },
  );

  testWidgets('empty title is rejected without creating a record', (
    WidgetTester tester,
  ) async {
    await pumpIris(tester);
    final Finder action = find.byKey(
      const ValueKey<String>('analyze-incident-button'),
    );
    await tester.ensureVisible(action);
    await tester.tap(action);
    await pumpUiTransition(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('confirm-case-title-button')),
    );
    await pumpUiTransition(tester);

    expect(find.text('Enter a case title.'), findsOneWidget);
    expect(
      await runOutsideFakeAsync(tester, harness.repository.getCases),
      isEmpty,
    );
  });

  testWidgets(
    'database failure is displayed as error rather than empty state',
    (WidgetTester tester) async {
      final IrisApplicationServices services = IrisApplicationServices(
        caseRepository: _FailingCaseRepository(),
      );
      await tester.pumpWidget(IrisApp(services: services));
      await pumpUntilStorageStateSettles(tester);

      expect(find.text('Recent cases unavailable'), findsOneWidget);
      expect(find.text('No cases yet'), findsNothing);

      await tester.tap(find.byKey(const ValueKey<String>('nav-cases')));
      await pumpUiTransition(tester);

      expect(find.text('Cases unavailable'), findsOneWidget);
      expect(find.text('No incident cases'), findsNothing);
    },
  );

  testWidgets('failed creation keeps entered title and permits retry', (
    WidgetTester tester,
  ) async {
    final _CreateFailingCaseRepository repository =
        _CreateFailingCaseRepository();
    final IrisApplicationServices services = IrisApplicationServices(
      caseRepository: repository,
    );
    await tester.pumpWidget(IrisApp(services: services));
    await pumpUntilStorageStateSettles(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('analyze-incident-button')),
    );
    await pumpUiTransition(tester);
    const String title = 'Test fixture: Retained after storage failure';
    await tester.enterText(
      find.byKey(const ValueKey<String>('case-title-field')),
      title,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('confirm-case-title-button')),
    );
    await pumpUntilFound(
      tester,
      find.text(
        'The case could not be saved. Check local storage and try again.',
      ),
    );

    final TextFormField titleField = tester.widget<TextFormField>(
      find.byKey(const ValueKey<String>('case-title-field')),
    );
    expect(titleField.controller?.text, title);
    expect(repository.createAttempts, 1);

    await tester.tap(
      find.byKey(const ValueKey<String>('confirm-case-title-button')),
    );
    await pumpUiTransition(tester);
    expect(repository.createAttempts, 2);
    expect(find.text('Create incident case'), findsOneWidget);
  });
}

class _FailingCaseRepository implements CaseRepository {
  StateError get _error => StateError('Controlled test storage failure.');

  @override
  Future<IncidentCase> createCase({required String title}) =>
      Future<IncidentCase>.error(_error);

  @override
  Future<bool> deleteCase(String id) => Future<bool>.error(_error);

  @override
  Future<IncidentCase?> getCaseById(String id) =>
      Future<IncidentCase?>.error(_error);

  @override
  Future<List<IncidentCase>> getCases({int? limit}) =>
      Future<List<IncidentCase>>.error(_error);

  @override
  Future<IncidentCase> renameCase({
    required String id,
    required String title,
  }) => Future<IncidentCase>.error(_error);
}

class _CreateFailingCaseRepository implements CaseRepository {
  int createAttempts = 0;

  StateError get _error => StateError('Controlled test storage failure.');

  @override
  Future<IncidentCase> createCase({required String title}) {
    createAttempts++;
    return Future<IncidentCase>.error(_error);
  }

  @override
  Future<bool> deleteCase(String id) => Future<bool>.error(_error);

  @override
  Future<IncidentCase?> getCaseById(String id) =>
      Future<IncidentCase?>.error(_error);

  @override
  Future<List<IncidentCase>> getCases({int? limit}) async =>
      const <IncidentCase>[];

  @override
  Future<IncidentCase> renameCase({
    required String id,
    required String title,
  }) => Future<IncidentCase>.error(_error);
}
