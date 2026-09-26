import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MainActivity guarantees native sqflite registration', () {
    final String source = File(
      'android/app/src/main/kotlin/com/iris/incidentreconstruction/'
      'MainActivity.kt',
    ).readAsStringSync();

    expect(source, contains('super.configureFlutterEngine(flutterEngine)'));
    expect(source, contains('SqflitePlugin::class.java'));
    expect(source, contains('flutterEngine.plugins.has'));
    expect(source, contains('flutterEngine.plugins.add'));
  });
}
