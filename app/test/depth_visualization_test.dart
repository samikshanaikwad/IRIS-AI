import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/depth/domain/depth_visualization.dart';

void main() {
  test('decodes finite Float32 depth and maps larger values nearer', () {
    final bytes = Float32List.fromList(<double>[0, 1, 2, 3]).buffer.asUint8List();
    final visualization = decodeDepthVisualization(
      bytes: bytes,
      tensorWidth: 2,
      tensorHeight: 2,
      originalWidth: 2,
      originalHeight: 2,
    );

    expect(visualization.displayValue(0, 0), 0);
    expect(visualization.displayValue(1, 1), 1);
  });

  test('rejects invalid length and non-finite values', () {
    expect(
      () => decodeDepthVisualization(
        bytes: Uint8List(3),
        tensorWidth: 1,
        tensorHeight: 1,
        originalWidth: 1,
        originalHeight: 1,
      ),
      throwsFormatException,
    );
    final bytes = Float32List.fromList(<double>[double.nan]).buffer.asUint8List();
    expect(
      () => decodeDepthVisualization(
        bytes: bytes,
        tensorWidth: 1,
        tensorHeight: 1,
        originalWidth: 1,
        originalHeight: 1,
      ),
      throwsFormatException,
    );
  });

  test('removes centered padding for portrait and landscape inputs', () {
    final bytes = Float32List.fromList(List<double>.filled(16, 1)).buffer.asUint8List();
    final portrait = decodeDepthVisualization(
      bytes: bytes,
      tensorWidth: 4,
      tensorHeight: 4,
      originalWidth: 1,
      originalHeight: 2,
    );
    final landscape = decodeDepthVisualization(
      bytes: bytes,
      tensorWidth: 4,
      tensorHeight: 4,
      originalWidth: 2,
      originalHeight: 1,
    );

    expect(portrait.cropWidth, 2);
    expect(portrait.cropHeight, 4);
    expect(portrait.cropLeft, 1);
    expect(landscape.cropWidth, 4);
    expect(landscape.cropHeight, 2);
    expect(landscape.cropTop, 1);
  });
}
