import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:iris/app/iris_app.dart';

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

  NavigationBar navigationBar(WidgetTester tester) {
    return tester.widget<NavigationBar>(find.byType(NavigationBar));
  }

  testWidgets('app launches into the shell with Home selected', (
    WidgetTester tester,
  ) async {
    await pumpIris(tester);

    expect(navigationBar(tester).selectedIndex, 0);
    expect(find.text('IRIS'), findsOneWidget);
    expect(
      find.text('Incident Reconstruction & Intelligence System'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('No cases yet'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('No cases yet'), findsOneWidget);
  });

  testWidgets('Cases navigation shows a database-backed empty state', (
    WidgetTester tester,
  ) async {
    await pumpIris(tester);

    await tester.tap(find.byKey(const ValueKey<String>('nav-cases')));
    await pumpUiTransition(tester);

    expect(navigationBar(tester).selectedIndex, 1);
    expect(find.text('No incident cases'), findsOneWidget);
    expect(find.text('Cases you create will appear here.'), findsOneWidget);
    expect(find.text('Start Incident Analysis'), findsOneWidget);
  });

  testWidgets('Capture navigation reports acquisition as unavailable', (
    WidgetTester tester,
  ) async {
    await pumpIris(tester);

    await tester.tap(find.byKey(const ValueKey<String>('nav-capture')));
    await pumpUiTransition(tester);

    expect(navigationBar(tester).selectedIndex, 2);
    expect(find.text('Evidence Capture'), findsOneWidget);
    expect(find.text('Not available yet'), findsNWidgets(2));

    final Finder captureButton = find.descendant(
      of: find.byKey(const ValueKey<String>('capture-scene-button')),
      matching: find.byWidgetPredicate((Widget widget) {
        return widget is FilledButton;
      }),
    );
    final Finder importButton = find.descendant(
      of: find.byKey(const ValueKey<String>('import-evidence-button')),
      matching: find.byWidgetPredicate((Widget widget) {
        return widget is OutlinedButton;
      }),
    );

    expect(tester.widget<FilledButton>(captureButton).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(importButton).onPressed, isNull);
  });

  testWidgets('More navigation shows factual product information', (
    WidgetTester tester,
  ) async {
    await pumpIris(tester);

    await tester.tap(find.byKey(const ValueKey<String>('nav-more')));
    await pumpUiTransition(tester);

    expect(navigationBar(tester).selectedIndex, 3);
    expect(find.text('About IRIS'), findsOneWidget);
    expect(
      find.text('AI-assisted incident reconstruction platform.'),
      findsOneWidget,
    );
  });

  testWidgets('Home action opens creation without persisting until confirmed', (
    WidgetTester tester,
  ) async {
    await pumpIris(tester);

    final Finder action = find.byKey(
      const ValueKey<String>('analyze-incident-button'),
    );
    await tester.ensureVisible(action);
    await tester.tap(action);
    await pumpUiTransition(tester);

    expect(find.text('Create incident case'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('case-title-field')),
      findsOneWidget,
    );
    expect(
      await runOutsideFakeAsync(tester, harness.repository.getCases),
      isEmpty,
    );
  });

  testWidgets('no fabricated recent incident record is rendered', (
    WidgetTester tester,
  ) async {
    await pumpIris(tester);

    expect(find.text('Case #001'), findsNothing);
    expect(find.text('Demo Accident'), findsNothing);
    expect(find.text('Highway Collision'), findsNothing);
    expect(find.text('Reconstruction complete'), findsNothing);
  });

  testWidgets('large text scale does not produce a layout exception', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: IrisApp(services: harness.services),
      ),
    );
    await pumpUntilStorageStateSettles(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('IRIS'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('nav-cases')));
    await pumpUiTransition(tester);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey<String>('nav-capture')));
    await pumpUiTransition(tester);
    expect(tester.takeException(), isNull);
  });
}
