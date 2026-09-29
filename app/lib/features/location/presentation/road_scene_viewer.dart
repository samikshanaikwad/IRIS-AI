import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../application/case_location_service.dart';
import '../domain/road_context.dart';
import '../../geometry/domain/evidence_world_alignment.dart';
import '../../geometry/domain/relative_geometry.dart';
import '../../geometry/application/relative_geometry_service.dart';
import '../../geometry/application/evidence_world_alignment_service.dart';
import '../../evidence/application/evidence_controller.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

class RoadSceneSection extends StatelessWidget {
  const RoadSceneSection({
    required this.caseId,
    required this.service,
    this.evidenceController,
    this.geometry,
    this.alignmentService,
    super.key,
  });
  final String caseId;
  final CaseLocationService service;
  final EvidenceController? evidenceController;
  final RelativeGeometryOperations? geometry;
  final EvidenceWorldAlignmentService? alignmentService;
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
    RelativeGeometry? evidenceGeometry;
    EvidenceWorldAlignment? alignment;
    final evidence = evidenceController?.items ?? const [];
    final geometryOps = geometry;
    final alignmentOps = alignmentService;
    if (geometryOps != null && alignmentOps != null && evidence.isNotEmpty) {
      for (final item in evidence) {
        final saved = await alignmentOps.load(item.id);
        final record = await geometryOps.load(item);
        if (saved == null || record == null) continue;
        final fingerprint = sha256
            .convert(
              utf8.encode(
                '${contextData.caseId}|${contextData.latitude}|${contextData.longitude}|${contextData.status}|${contextData.json}',
              ),
            )
            .toString();
        if (saved.isStale(
          geometrySha256: record.sha256,
          roadContextFingerprint: fingerprint,
        ))
          continue;
        try {
          evidenceGeometry = await geometryOps.read(record);
          alignment = saved;
        } on Object {
          evidenceGeometry = null;
          alignment = null;
        }
        if (evidenceGeometry != null) break;
      }
    }
    if (!context.mounted) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RoadSceneViewer(
          contextData: contextData,
          evidenceGeometry: evidenceGeometry,
          alignment: alignment,
        ),
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
  const RoadSceneViewer({
    required this.contextData,
    this.evidenceGeometry,
    this.alignment,
    super.key,
  });
  final RoadContext contextData;
  final RelativeGeometry? evidenceGeometry;
  final EvidenceWorldAlignment? alignment;
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
              painter: _RoadPainter(
                widget.contextData,
                yaw,
                pitch,
                zoom,
                widget.evidenceGeometry,
                widget.alignment,
              ),
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
              Text('Evidence geometry: Image-derived relative geometry'),
              Text('Alignment: User supplied / uncalibrated'),
              Text('Scale relationship: User-supplied relative-to-world scale'),
            ],
          ),
        ),
      ],
    ),
  );
}

class _RoadPainter extends CustomPainter {
  const _RoadPainter(
    this.data,
    this.yaw,
    this.pitch,
    this.zoom,
    this.geometry,
    this.alignment,
  );
  final RoadContext data;
  final double yaw, pitch, zoom;
  final RelativeGeometry? geometry;
  final EvidenceWorldAlignment? alignment;
  @override
  void paint(Canvas canvas, Size size) {
    final points = data.roads.expand((r) => r.localCoordinates).toList();
    if (points.isEmpty) return;
    var minX = points.map((p) => p[0]).reduce(math.min),
        maxX = points.map((p) => p[0]).reduce(math.max),
        minZ = points.map((p) => p[1]).reduce(math.min),
        maxZ = points.map((p) => p[1]).reduce(math.max);
    final evidencePoints = geometry == null || alignment == null
        ? const <RelativePoint>[]
        : geometry!.points.map(alignment!.transform).toList();
    for (final p in evidencePoints) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minZ = math.min(minZ, p.z);
      maxZ = math.max(maxZ, p.z);
    }
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
    if (evidencePoints.isNotEmpty) {
      final evidencePaint = Paint()..color = Colors.cyanAccent;
      for (final point in evidencePoints) {
        canvas.drawCircle(project(point.x, point.z), 2.2, evidencePaint);
      }
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
