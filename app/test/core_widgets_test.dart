import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:iris/app/theme/iris_theme.dart';
import 'package:iris/core/widgets/iris_button.dart';
import 'package:iris/core/widgets/iris_card.dart';
import 'package:iris/core/widgets/iris_empty_state.dart';
import 'package:iris/core/widgets/iris_status_chip.dart';

void main() {
  testWidgets('core components render and expose disabled state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: IrisTheme.dark,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                IrisCard(child: Text('Card content')),
                IrisStatusChip(label: 'Unavailable'),
                IrisPrimaryButton(
                  key: ValueKey<String>('disabled-primary'),
                  label: 'Unavailable action',
                  onPressed: null,
                ),
                IrisEmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'Nothing here',
                  message: 'Content will appear when it exists.',
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Card content'), findsOneWidget);
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('Nothing here'), findsOneWidget);

    final Finder button = find.descendant(
      of: find.byKey(const ValueKey<String>('disabled-primary')),
      matching: find.byType(FilledButton),
    );
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
  });
}
