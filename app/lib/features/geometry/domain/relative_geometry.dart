import 'dart:typed_data';

class RelativePoint {
  const RelativePoint({
    required this.x,
    required this.y,
    required this.z,
    required this.u,
    required this.v,
  });
  final double x, y, z, u, v;
}

class RelativeGeometry {
  const RelativeGeometry({
    required this.points,
    required this.evidenceId,
    required this.depthSha256,
    required this.depthAnalyzedAt,
    required this.width,
    required this.height,
  });
  final List<RelativePoint> points;
  final String evidenceId, depthSha256;
  final DateTime depthAnalyzedAt;
  final int width, height;
}

RelativeGeometry buildRelativeGeometry({
  required String evidenceId,
  required String depthSha256,
  required DateTime depthAnalyzedAt,
  required Float32List depth,
  required int depthWidth,
  required int depthHeight,
  required int originalWidth,
  required int originalHeight,
  int maxPoints = 2048,
}) {
  if (depth.length != depthWidth * depthHeight ||
      originalWidth <= 0 ||
      originalHeight <= 0)
    throw const FormatException('Depth geometry input is invalid.');
  var min = double.infinity, max = double.negativeInfinity;
  for (final value in depth) {
    if (!value.isFinite)
      throw const FormatException('Depth contains non-finite values.');
    if (value < min) min = value;
    if (value > max) max = value;
  }
  if (!(max > min)) throw const FormatException('Depth range is degenerate.');
  final stride = (depth.length / maxPoints).ceil().clamp(1, depth.length);
  final points = <RelativePoint>[];
  final scale = (depthWidth / originalWidth < depthHeight / originalHeight)
      ? depthWidth / originalWidth
      : depthHeight / originalHeight;
  final validWidth = (originalWidth * scale).round().clamp(1, depthWidth);
  final validHeight = (originalHeight * scale).round().clamp(1, depthHeight);
  final left = (depthWidth - validWidth) ~/ 2,
      top = (depthHeight - validHeight) ~/ 2;
  for (var index = 0; index < depth.length; index += stride) {
    final py = index ~/ depthWidth, px = index % depthWidth;
    if (px < left ||
        py < top ||
        px >= left + validWidth ||
        py >= top + validHeight)
      continue;
    final nearer = (depth[index] - min) / (max - min);
    final z = 1.0 / nearer.clamp(0.02, 1.0);
    final u = (px + .5) / depthWidth, v = (py + .5) / depthHeight;
    points.add(
      RelativePoint(x: (u - .5) * z, y: (v - .5) * z, z: z, u: u, v: v),
    );
  }
  if (points.isEmpty) throw const FormatException('No valid geometry points.');
  return RelativeGeometry(
    points: List.unmodifiable(points),
    evidenceId: evidenceId,
    depthSha256: depthSha256,
    depthAnalyzedAt: depthAnalyzedAt,
    width: originalWidth,
    height: originalHeight,
  );
}
