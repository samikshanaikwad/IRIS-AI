import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../domain/relative_geometry.dart';

class RelativeGeometryViewer extends StatefulWidget { const RelativeGeometryViewer({required this.geometry, super.key}); final RelativeGeometry geometry; @override State<RelativeGeometryViewer> createState() => _RelativeGeometryViewerState(); }
class _RelativeGeometryViewerState extends State<RelativeGeometryViewer> {
  double yaw = .35, pitch = -.15, zoom = 1;
  @override Widget build(BuildContext context) => GestureDetector(onPanUpdate: (d) => setState(() { yaw += d.delta.dx * .01; pitch += d.delta.dy * .01; }), onDoubleTap: () => setState(() { yaw = .35; pitch = -.15; zoom = 1; }), child: AspectRatio(aspectRatio: 1.4, child: CustomPaint(painter: _PointPainter(widget.geometry.points, yaw, pitch, zoom), child: const Center(child: Text('Double tap to reset', style: TextStyle(color: Colors.white54))))));
}
class _PointPainter extends CustomPainter {
  const _PointPainter(this.points, this.yaw, this.pitch, this.zoom);
  final List<RelativePoint> points;
  final double yaw, pitch, zoom;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.lightBlueAccent;
    final cy = math.cos(yaw), sy = math.sin(yaw);
    final cp = math.cos(pitch), sp = math.sin(pitch);
    final projected = <({Offset p, double z})>[];
    for (final point in points) {
      final x = point.x * cy - point.z * sy;
      final z0 = point.x * sy + point.z * cy;
      final y = point.y * cp - z0 * sp;
      final z = point.y * sp + z0 * cp;
      final scale = size.shortestSide * .22 * zoom / (1.0 + z.abs());
      projected.add((p: Offset(size.width / 2 + x * scale, size.height / 2 + y * scale), z: z));
    }
    projected.sort((a, b) => a.z.compareTo(b.z));
    for (final item in projected) {
      canvas.drawCircle(item.p, 1.5, paint);
    }
  }
  @override bool shouldRepaint(covariant _PointPainter old) => old.yaw != yaw || old.pitch != pitch || old.zoom != zoom || old.points != points;
}
