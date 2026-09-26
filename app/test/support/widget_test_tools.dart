import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<T> runOutsideFakeAsync<T>(
  WidgetTester tester,
  Future<T> Function() operation,
) async {
  final T? result = await tester.runAsync<T>(operation);
  if (result == null) {
    throw TestFailure('The external asynchronous operation returned null.');
  }
  return result;
}

Future<void> pumpUiTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> pumpUntilStorageStateSettles(WidgetTester tester) async {
  for (int attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync<void>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    });
    await tester.pump(const Duration(milliseconds: 20));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      return;
    }
  }

  throw TestFailure('Local storage did not leave its loading state.');
}

Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  String? failureMessage,
}) async {
  for (int attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync<void>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    });
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) {
      await pumpUiTransition(tester);
      return;
    }
  }

  throw TestFailure(failureMessage ?? 'Expected UI state did not appear.');
}
