import 'package:flutter_test/flutter_test.dart';

import 'package:iris/app/iris_app.dart';

void main() {
  testWidgets('IRIS root application and foundation screen render', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const IrisApp());

    expect(find.text('IRIS'), findsOneWidget);
    expect(
      find.text('Incident Reconstruction & Intelligence System'),
      findsOneWidget,
    );
    expect(find.text('Foundation initialized'), findsOneWidget);
    expect(
      find.text('You have pushed the button this many times:'),
      findsNothing,
    );
  });
}
