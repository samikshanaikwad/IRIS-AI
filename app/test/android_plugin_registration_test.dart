import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MainActivity delegates plugin registration to Flutter embedding', () {
    final String source = File(
      'android/app/src/main/kotlin/com/iris/incidentreconstruction/'
      'MainActivity.kt',
    ).readAsStringSync();

    expect(source, contains('class MainActivity : FlutterActivity()'));
    expect(source, isNot(contains('SqflitePlugin')));
    expect(source, isNot(contains('configureFlutterEngine')));
  });

  test('Flutter dependency metadata includes native sqflite for Android', () {
    final File metadataFile = File('.flutter-plugins-dependencies');
    expect(
      metadataFile.existsSync(),
      isTrue,
      reason: 'flutter pub get must generate plugin dependency metadata',
    );

    final Map<String, Object?> metadata =
        jsonDecode(metadataFile.readAsStringSync()) as Map<String, Object?>;
    final Map<String, Object?> plugins =
        metadata['plugins']! as Map<String, Object?>;
    final List<Object?> androidPlugins = plugins['android']! as List<Object?>;
    final Map<String, Object?> sqflitePlugin = androidPlugins
        .cast<Map<String, Object?>>()
        .singleWhere((Map<String, Object?> plugin) {
          return plugin['name'] == 'sqflite_android';
        });

    expect(sqflitePlugin['native_build'], isTrue);
    expect(sqflitePlugin['dev_dependency'], isFalse);
  });

  test('generated Android registrant contains the resolved sqflite class', () {
    final File registrant = File(
      'android/app/src/main/java/io/flutter/plugins/'
      'GeneratedPluginRegistrant.java',
    );
    expect(
      registrant.existsSync(),
      isTrue,
      reason: 'Flutter must generate the Android plugin registrant',
    );

    final String source = registrant.readAsStringSync();
    expect(source, contains('new com.tekartik.sqflite.SqflitePlugin()'));
  });

  test('Android project keeps standard Flutter plugin Gradle wiring', () {
    final String settings = File(
      'android/settings.gradle.kts',
    ).readAsStringSync();
    final String appBuild = File(
      'android/app/build.gradle.kts',
    ).readAsStringSync();

    expect(settings, contains('dev.flutter.flutter-plugin-loader'));
    expect(appBuild, contains('dev.flutter.flutter-gradle-plugin'));
  });
}
