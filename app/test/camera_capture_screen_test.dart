import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:iris/features/evidence/data/camera_gateway.dart';
import 'package:iris/features/evidence/presentation/camera_capture_screen.dart';

void main() {
  testWidgets('no camera renders an honest unavailable state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CameraCaptureScreen(cameraGateway: _NoCameraGateway()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Camera unavailable'), findsOneWidget);
    expect(
      find.text(
        'The camera is unavailable. Try again or import evidence instead.',
      ),
      findsOneWidget,
    );
    expect(find.byType(CameraPreview), findsNothing);
  });

  test('camera denial message does not claim capture success', () {
    expect(
      cameraFailureMessage('CameraAccessDenied'),
      contains('Camera permission is required'),
    );
    expect(
      cameraFailureMessage('CameraAccessDeniedWithoutPrompt'),
      contains('Android settings'),
    );
  });

  test('restricted camera has a distinct truthful message', () {
    expect(
      cameraFailureMessage('CameraAccessRestricted'),
      'Camera access is restricted on this device.',
    );
  });
}

class _NoCameraGateway implements CameraDiscoveryGateway {
  const _NoCameraGateway();

  @override
  Future<List<CameraDescription>> available() async =>
      const <CameraDescription>[];
}
