import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MainActivity invokes the generated Flutter plugin registrant', () {
    final String source = File(
      'android/app/src/main/kotlin/com/iris/incidentreconstruction/'
      'MainActivity.kt',
    ).readAsStringSync();

    expect(source, contains('class MainActivity : FlutterActivity()'));
    expect(source, contains('override fun configureFlutterEngine'));
    expect(
      source,
      contains('GeneratedPluginRegistrant.registerWith(flutterEngine)'),
    );
    expect(source, isNot(contains('SqflitePlugin()')));
    expect(source, isNot(contains('import com.tekartik.sqflite')));
  });

  test('environment diagnostics remain count-only and debug-only', () {
    final String source = File(
      'android/app/src/main/kotlin/com/iris/incidentreconstruction/'
      'MainActivity.kt',
    ).readAsStringSync();

    expect(source, contains('ApplicationInfo.FLAG_DEBUGGABLE'));
    expect(source, contains('com.iris.debug/environment'));
    expect(source, contains('IRISEnvironment'));
    expect(source, contains('message.length <= 1000'));
  });

  test('Flutter dependency metadata includes required Android plugins', () {
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
    final Set<Object?> names = androidPlugins
        .cast<Map<String, Object?>>()
        .map((Map<String, Object?> plugin) => plugin['name'])
        .toSet();
    expect(
      names,
      containsAll(<String>{
        'camera_android_camerax',
        'image_picker_android',
        'path_provider_android',
        'sqflite_android',
      }),
    );
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
    expect(
      source,
      contains('new io.flutter.plugins.camerax.CameraAndroidCameraxPlugin()'),
    );
    expect(
      source,
      contains('new io.flutter.plugins.imagepicker.ImagePickerPlugin()'),
    );
    expect(source, contains('new com.github.dart_lang.jni.JniPlugin()'));
    expect(
      source,
      contains('new com.github.dart_lang.jni_flutter.JniFlutterPlugin()'),
    );
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
    expect(appBuild, contains('verifyIrisGeneratedPluginRegistration'));
  });

  test('Android manifest limits acquisition permissions', () {
    final String manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android.permission.CAMERA'));
    expect(manifest, contains('android.permission.RECORD_AUDIO'));
    expect(manifest, contains('android.permission.READ_EXTERNAL_STORAGE'));
    expect(manifest, contains('android.permission.WRITE_EXTERNAL_STORAGE'));
    expect(
      RegExp(
        r'android:name="android.permission.RECORD_AUDIO"\s+tools:node="remove"',
      ).hasMatch(manifest),
      isTrue,
    );
    expect(
      RegExp(
        r'android:name="android.permission.READ_EXTERNAL_STORAGE"\s+tools:node="remove"',
      ).hasMatch(manifest),
      isTrue,
    );
    expect(
      RegExp(
        r'android:name="android.permission.WRITE_EXTERNAL_STORAGE"\s+tools:node="remove"',
      ).hasMatch(manifest),
      isTrue,
    );
    expect(manifest, contains('android:required="false"'));
    expect(
      manifest,
      contains('android.permission.ACCESS_FINE_LOCATION'),
    );
    expect(
      manifest,
      contains('android.permission.ACCESS_COARSE_LOCATION'),
    );
  });
}
