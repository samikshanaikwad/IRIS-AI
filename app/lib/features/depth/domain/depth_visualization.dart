import 'dart:math' as math;
import 'dart:typed_data';

class EvidenceDepthVisualization {
  const EvidenceDepthVisualization({
    required this.values,
    required this.width,
    required this.height,
    required this.originalWidth,
    required this.originalHeight,
    required this.cropLeft,
    required this.cropTop,
    required this.cropWidth,
    required this.cropHeight,
    required this.min,
    required this.max,
  });

  final Float32List values;
  final int width;
  final int height;
  final int originalWidth;
  final int originalHeight;
  final int cropLeft;
  final int cropTop;
  final int cropWidth;
  final int cropHeight;
  final double min;
  final double max;

  double displayValue(int x, int y) {
    final value = values[(cropTop + y) * width + cropLeft + x];
    if (max <= min) return 0.0;
    return ((value - min) / (max - min)).clamp(0.0, 1.0);
  }
}

EvidenceDepthVisualization decodeDepthVisualization({
  required Uint8List bytes,
  required int tensorWidth,
  required int tensorHeight,
  required int originalWidth,
  required int originalHeight,
}) {
  if (tensorWidth <= 0 || tensorHeight <= 0 ||
      originalWidth <= 0 || originalHeight <= 0) {
    throw const FormatException('Depth dimensions are invalid.');
  }
  final expectedBytes = tensorWidth * tensorHeight * 4;
  if (bytes.length != expectedBytes) {
    throw const FormatException('Depth file length is invalid.');
  }
  final values = Float32List.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes ~/ 4);
  var minValue = double.infinity;
  var maxValue = double.negativeInfinity;
  for (final value in values) {
    if (!value.isFinite) throw const FormatException('Depth contains non-finite values.');
    minValue = math.min(minValue, value);
    maxValue = math.max(maxValue, value);
  }
  final scale = math.min(tensorWidth / originalWidth, tensorHeight / originalHeight);
  final validWidth = math.max(1, (originalWidth * scale).round());
  final validHeight = math.max(1, (originalHeight * scale).round());
  final cropWidth = math.min(tensorWidth, validWidth);
  final cropHeight = math.min(tensorHeight, validHeight);
  return EvidenceDepthVisualization(
    values: values,
    width: tensorWidth,
    height: tensorHeight,
    originalWidth: originalWidth,
    originalHeight: originalHeight,
    cropLeft: (tensorWidth - cropWidth) ~/ 2,
    cropTop: (tensorHeight - cropHeight) ~/ 2,
    cropWidth: cropWidth,
    cropHeight: cropHeight,
    min: minValue,
    max: maxValue,
  );
}
