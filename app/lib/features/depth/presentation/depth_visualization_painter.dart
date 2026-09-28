import 'package:flutter/material.dart';
import '../domain/depth_visualization.dart';

class DepthVisualizationPainter extends CustomPainter {
  const DepthVisualizationPainter(this.visualization);
  final EvidenceDepthVisualization visualization;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..filterQuality = FilterQuality.low;
    final cellWidth = size.width / visualization.cropWidth;
    final cellHeight = size.height / visualization.cropHeight;
    for (var y = 0; y < visualization.cropHeight; y++) {
      for (var x = 0; x < visualization.cropWidth; x++) {
        final nearer = visualization.displayValue(x, y);
        paint.color = Color.lerp(Colors.black, Colors.white, nearer)!;
        canvas.drawRect(
          Rect.fromLTWH(x * cellWidth, y * cellHeight, cellWidth + 1, cellHeight + 1),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant DepthVisualizationPainter oldDelegate) =>
      oldDelegate.visualization.values != visualization.values;
}
