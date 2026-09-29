import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../application/case_location_service.dart';
import '../domain/road_context.dart';

class RoadSceneSection extends StatelessWidget {
  const RoadSceneSection({
    required this.caseId,
    required this.service,
    super.key,
  });
  final String caseId;
  final CaseLocationService service;
  Future<void> _open(BuildContext context) async {
    final contextData = await service.loadRoadContext(caseId);
    if (!context.mounted) return;
    if (contextData == null || contextData.status != 'AVAILABLE') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '3D road environment unavailable — no map-derived road geometry.',
          ),
        ),
      );
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RoadSceneViewer(contextData: contextData),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '3D RECONSTRUCTION',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Real map-derived road environment. Evidence geometry alignment pending.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _open(context),
            icon: const Icon(Icons.view_in_ar),
            label: const Text('Open 3D Reconstruction'),
          ),
        ],
      ),
    ),
  );
}

class RoadSceneViewer extends StatefulWidget {
  const RoadSceneViewer({required this.contextData, super.key});
  final RoadContext contextData;
  @override
  State<RoadSceneViewer> createState() => _RoadSceneViewerState();
}

class _RoadSceneViewerState extends State<RoadSceneViewer> {
  double yaw = .35, pitch = -.35, zoom = 1;
  void reset() => setState(() {
    yaw = .35;
    pitch = -.35;
    zoom = 1;
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('3D Reconstruction'),
      actions: [
        IconButton(
          onPressed: reset,
          tooltip: 'Reset camera',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        Expanded(
          child: GestureDetector(
            onScaleUpdate: (d) => setState(() {
              yaw += d.focalPointDelta.dx * .01;
              pitch += d.focalPointDelta.dy * .01;
              zoom = (zoom * d.scale).clamp(.5, 4.0);
            }),
            onDoubleTap: reset,
            child: CustomPaint(
              painter: _RoadPainter(widget.contextData, yaw, pitch, zoom),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Environment source: OpenStreetMap-derived road geometry'),
              Text(
                'Coordinate frame: Local metric (metres from geographic coordinates)',
              ),
              Text('Incident location reference at world origin'),
              Text('Evidence alignment: Not established'),
              Text('Scale: Map-derived local metric geometry'),
            ],
          ),
        ),
      ],
    ),
  );
}

class _RoadPainter extends CustomPainter {
  const _RoadPainter(this.data, this.yaw, this.pitch, this.zoom);
  final RoadContext data;
  final double yaw, pitch, zoom;
  @override
  void paint(Canvas canvas, Size size) {
    final points = data.roads.expand((r) => r.localCoordinates).toList();
    if (points.isEmpty) return;
    var minX = points.map((p) => p[0]).reduce(math.min),
        maxX = points.map((p) => p[0]).reduce(math.max),
        minZ = points.map((p) => p[1]).reduce(math.min),
        maxZ = points.map((p) => p[1]).reduce(math.max);
    final span = math.max(maxX - minX, maxZ - minZ).clamp(1.0, double.infinity);
    final centerX = (minX + maxX) / 2, centerZ = (minZ + maxZ) / 2;
    final scale = size.shortestSide * .72 * zoom / span;
    final cy = math.cos(yaw),
        sy = math.sin(yaw),
        cp = math.cos(pitch),
        sp = math.sin(pitch);
    Offset project(double x, double z) {
      final rx = (x - centerX) * cy - (z - centerZ) * sy;
      final rz = (x - centerX) * sy + (z - centerZ) * cy;
      final y = -rz * sp;
      final depth = rz * cp;
      return Offset(
        size.width / 2 + rx * scale / (1 + depth.abs() * .01),
        size.height / 2 + y * scale / (1 + depth.abs() * .01),
      );
    }

    final grid = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;
    for (var i = -10; i <= 10; i++) {
      final a = project(i * span / 10, -span),
          b = project(i * span / 10, span),
          c = project(-span, i * span / 10),
          d = project(span, i * span / 10);
      canvas.drawLine(a, b, grid);
      canvas.drawLine(c, d, grid);
    }
    final road = Paint()
      ..color = Colors.amberAccent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    for (final segment in data.roads) {
      final path = Path();
      for (var i = 0; i < segment.localCoordinates.length; i++) {
        final p = project(
          segment.localCoordinates[i][0],
          segment.localCoordinates[i][1],
        );
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, road);
    }
    final origin = project(0, 0);
    canvas.drawCircle(origin, 7, Paint()..color = Colors.redAccent);
    canvas.drawCircle(
      origin,
      11,
      Paint()
        ..color = Colors.redAccent.withValues(alpha: .25)
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _RoadPainter old) =>
      old.data != data ||
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.zoom != zoom;
}
