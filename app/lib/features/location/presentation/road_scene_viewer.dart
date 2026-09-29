import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../application/case_location_service.dart';
import '../domain/road_context.dart';
import '../../geometry/domain/evidence_world_alignment.dart';
import '../../geometry/domain/relative_geometry.dart';
import '../../geometry/domain/evidence_vehicle_marker.dart';
import '../../geometry/application/relative_geometry_service.dart';
import '../../geometry/application/evidence_world_alignment_service.dart';
import '../../detection/application/evidence_detection_service.dart';
import '../../detection/domain/evidence_detection.dart';
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
    this.detection,
    super.key,
  });
  final String caseId;
  final CaseLocationService service;
  final EvidenceController? evidenceController;
  final RelativeGeometryOperations? geometry;
  final EvidenceWorldAlignmentService? alignmentService;
  final EvidenceDetectionOperations? detection;
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
    List<EvidenceVehicleMarker> markers = const [];
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
        if (evidenceGeometry != null) {
          final detectionOps = detection;
          if (detectionOps != null) {
            final snapshot = await detectionOps.load(item);
            if (snapshot.state == DetectionState.complete &&
                snapshot.analysis != null) {
              markers = deriveVehicleMarkers(
                analysis: snapshot.analysis!,
                geometry: evidenceGeometry,
                alignment: saved,
              );
            }
          }
          break;
        }
      }
    }
    if (!context.mounted) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RoadSceneViewer(
          contextData: contextData,
          evidenceGeometry: evidenceGeometry,
          alignment: alignment,
          vehicleMarkers: markers,
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
    this.vehicleMarkers = const [],
    super.key,
  });
  final RoadContext contextData;
  final RelativeGeometry? evidenceGeometry;
  final EvidenceWorldAlignment? alignment;
  final List<EvidenceVehicleMarker> vehicleMarkers;
  @override
  State<RoadSceneViewer> createState() => _RoadSceneViewerState();
}

class _RoadSceneViewerState extends State<RoadSceneViewer> {
  double yaw = .35, pitch = -.35, zoom = 1;
  bool showEvidence = false, showRoad = true, showGrid = false;
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
                widget.vehicleMarkers,
                showEvidence,
                showRoad,
                showGrid,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('Scene'),
                    selected: true,
                    onSelected: (_) {},
                  ),
                  FilterChip(
                    label: const Text('Evidence geometry'),
                    selected: showEvidence,
                    onSelected: (v) => setState(() => showEvidence = v),
                  ),
                  FilterChip(
                    label: const Text('Road centerlines'),
                    selected: showRoad,
                    onSelected: (v) => setState(() => showRoad = v),
                  ),
                  FilterChip(
                    label: const Text('World grid'),
                    selected: showGrid,
                    onSelected: (v) => setState(() => showGrid = v),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Environment source: OpenStreetMap-derived road geometry'),
              Text(
                'Coordinate frame: Local metric (metres from geographic coordinates)',
              ),
              Text('Incident location reference at world origin'),
              Text('Evidence geometry: Image-derived relative geometry'),
              Text('Alignment: User supplied / uncalibrated'),
              Text('Scale relationship: User-supplied relative-to-world scale'),
              Text(
                'Detected vehicle marker: Evidence anchored / representational',
              ),
              Text(
                'Vehicle dimensions: Not measured • Orientation: Not established',
              ),
              const Text(
                'Reference plane: Visualization only • terrain elevation unavailable',
              ),
              Text(
                widget.contextData.roads.any((road) => road.width == null)
                    ? 'Road surface width: Representational / not established where OSM width is absent'
                    : 'Road surface width: Map-derived from explicit OSM width',
              ),
              if (widget.vehicleMarkers.isEmpty)
                Text(
                  'No eligible vehicle detections available for 3D representation.',
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Render-only 3D primitives. Their dimensions are never analytical evidence.
/// Future physics must use its own calibrated/evidence-backed data model.
class _ScenePoint {
  const _ScenePoint(this.x, this.y, this.z);
  final double x, y, z;
  _ScenePoint operator +(_ScenePoint other) =>
      _ScenePoint(x + other.x, y + other.y, z + other.z);
}

class _ProjectedPoint {
  const _ProjectedPoint(this.offset, this.depth);
  final Offset offset;
  final double depth;
}

class _SceneFace {
  const _SceneFace(this.points, this.color);
  final List<_ScenePoint> points;
  final Color color;
}

class _RoadPainter extends CustomPainter {
  const _RoadPainter(
    this.data,
    this.yaw,
    this.pitch,
    this.zoom,
    this.geometry,
    this.alignment,
    this.vehicleMarkers,
    this.showEvidence,
    this.showRoad,
    this.showGrid,
  );
  final RoadContext data;
  final double yaw, pitch, zoom;
  final RelativeGeometry? geometry;
  final EvidenceWorldAlignment? alignment;
  final List<EvidenceVehicleMarker> vehicleMarkers;
  final bool showEvidence, showRoad, showGrid;
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
    for (final marker in vehicleMarkers) {
      minX = math.min(minX, marker.worldAnchor.x);
      maxX = math.max(maxX, marker.worldAnchor.x);
      minZ = math.min(minZ, marker.worldAnchor.z);
      maxZ = math.max(maxZ, marker.worldAnchor.z);
    }
    final hasIncidentFocus =
        evidencePoints.isNotEmpty || vehicleMarkers.isNotEmpty;
    final focusX = evidencePoints.isNotEmpty
        ? evidencePoints.map((p) => p.x).reduce((a, b) => a + b) /
              evidencePoints.length
        : vehicleMarkers.isNotEmpty
        ? vehicleMarkers.map((m) => m.worldAnchor.x).reduce((a, b) => a + b) /
              vehicleMarkers.length
        : 0.0;
    final focusZ = evidencePoints.isNotEmpty
        ? evidencePoints.map((p) => p.z).reduce((a, b) => a + b) /
              evidencePoints.length
        : vehicleMarkers.isNotEmpty
        ? vehicleMarkers.map((m) => m.worldAnchor.z).reduce((a, b) => a + b) /
              vehicleMarkers.length
        : 0.0;
    final evidenceSpan = hasIncidentFocus
        ? math.max(
            evidencePoints.isEmpty
                ? 0
                : (evidencePoints.map((p) => p.x).reduce(math.max) -
                      evidencePoints.map((p) => p.x).reduce(math.min)),
            evidencePoints.isEmpty
                ? 0
                : (evidencePoints.map((p) => p.z).reduce(math.max) -
                      evidencePoints.map((p) => p.z).reduce(math.min)),
          )
        : 0;
    final span =
        (hasIncidentFocus
                ? math.max(evidenceSpan * 3.0, 12.0)
                : math.max(maxX - minX, maxZ - minZ))
            .clamp(1.0, double.infinity);
    final centerX = hasIncidentFocus ? focusX : (minX + maxX) / 2;
    final centerZ = hasIncidentFocus ? focusZ : (minZ + maxZ) / 2;
    final camera = _SceneCamera(
      target: _ScenePoint(centerX, 0, centerZ),
      yaw: yaw,
      pitch: pitch.clamp(-1.25, .15),
      distance: span * 1.25 / zoom,
      viewport: size,
    );

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xff10161d),
    );
    final faces = <_SceneFace>[
      ..._cuboid(
        _ScenePoint(centerX, -.45, centerZ),
        span * 1.25,
        .45,
        span * 1.25,
        const Color(0xff26313a),
        const Color(0xff172028),
      ),
    ];
    for (final segment in data.roads) {
      final width =
          segment.width ?? 6.0; // Display-only when OSM width is absent.
      for (var i = 1; i < segment.localCoordinates.length; i++) {
        final a = segment.localCoordinates[i - 1];
        final b = segment.localCoordinates[i];
        faces.addAll(_roadSlab(a[0], a[1], b[0], b[1], width));
      }
    }
    for (final marker in vehicleMarkers) {
      faces.addAll(_vehicleMesh(marker));
    }
    // The incident marker is a 3D reference, not a collision/impact point.
    faces.addAll(
      _cuboid(
        const _ScenePoint(0, .3, 0),
        .45,
        .6,
        .45,
        Colors.redAccent,
        const Color(0xff7d2030),
      ),
    );
    _drawFaces(canvas, camera, faces);
    if (showGrid) _drawGrid(canvas, camera, span);
    if (showRoad) _drawCenterlines(canvas, camera);
    if (showEvidence && evidencePoints.isNotEmpty) {
      final evidencePaint = Paint()..color = Colors.cyanAccent;
      for (final point in evidencePoints) {
        final projected = camera.project(
          _ScenePoint(point.x, point.y, point.z),
        );
        if (projected != null) {
          canvas.drawCircle(projected.offset, 2.2, evidencePaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RoadPainter old) =>
      old.data != data ||
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.zoom != zoom ||
      old.showEvidence != showEvidence ||
      old.showRoad != showRoad ||
      old.showGrid != showGrid;

  void _drawFaces(Canvas canvas, _SceneCamera camera, List<_SceneFace> faces) {
    final projected =
        <({List<_ProjectedPoint> points, Color color, double depth})>[];
    for (final face in faces) {
      final points = face.points
          .map(camera.project)
          .whereType<_ProjectedPoint>()
          .toList();
      if (points.length == face.points.length) {
        projected.add((
          points: points,
          color: face.color,
          depth:
              points.map((p) => p.depth).reduce((a, b) => a + b) /
              points.length,
        ));
      }
    }
    projected.sort((a, b) => b.depth.compareTo(a.depth));
    for (final face in projected) {
      final path = Path()
        ..moveTo(face.points.first.offset.dx, face.points.first.offset.dy);
      for (final point in face.points.skip(1)) {
        path.lineTo(point.offset.dx, point.offset.dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = face.color);
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.black26
          ..style = PaintingStyle.stroke
          ..strokeWidth = .7,
      );
    }
  }

  void _drawGrid(Canvas canvas, _SceneCamera camera, double span) {
    final paint = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;
    for (var i = -10; i <= 10; i++) {
      _line(
        canvas,
        camera,
        _ScenePoint(i * span / 10, .01, -span),
        _ScenePoint(i * span / 10, .01, span),
        paint,
      );
      _line(
        canvas,
        camera,
        _ScenePoint(-span, .01, i * span / 10),
        _ScenePoint(span, .01, i * span / 10),
        paint,
      );
    }
  }

  void _drawCenterlines(Canvas canvas, _SceneCamera camera) {
    final paint = Paint()
      ..color = Colors.amberAccent
      ..strokeWidth = 2;
    for (final road in data.roads) {
      for (var i = 1; i < road.localCoordinates.length; i++) {
        final a = road.localCoordinates[i - 1], b = road.localCoordinates[i];
        _line(
          canvas,
          camera,
          _ScenePoint(a[0], .04, a[1]),
          _ScenePoint(b[0], .04, b[1]),
          paint,
        );
      }
    }
  }

  void _line(
    Canvas canvas,
    _SceneCamera camera,
    _ScenePoint a,
    _ScenePoint b,
    Paint paint,
  ) {
    final pa = camera.project(a), pb = camera.project(b);
    if (pa != null && pb != null) canvas.drawLine(pa.offset, pb.offset, paint);
  }

  List<_SceneFace> _roadSlab(
    double ax,
    double az,
    double bx,
    double bz,
    double width,
  ) {
    final dx = bx - ax, dz = bz - az, length = math.sqrt(dx * dx + dz * dz);
    if (length == 0) return const [];
    final nx = -dz / length * width / 2, nz = dx / length * width / 2;
    final top = <_ScenePoint>[
      _ScenePoint(ax + nx, .05, az + nz),
      _ScenePoint(bx + nx, .05, bz + nz),
      _ScenePoint(bx - nx, .05, bz - nz),
      _ScenePoint(ax - nx, .05, az - nz),
    ];
    final bottom = top.map((p) => _ScenePoint(p.x, -.12, p.z)).toList();
    return _prism(
      top,
      bottom,
      const Color(0xff4d5963),
      const Color(0xff27323a),
    );
  }

  List<_SceneFace> _vehicleMesh(EvidenceVehicleMarker marker) {
    final p = marker.worldAnchor;
    const top = Color(0xff72c6e8), side = Color(0xff2e7396);
    List<_SceneFace> box(
      double dx,
      double dy,
      double dz,
      double x,
      double y,
      double z,
    ) => _cuboid(_ScenePoint(p.x + x, p.y + y, p.z + z), dx, dy, dz, top, side);
    // These class proportions are display-only, neutral-orientation proxies.
    return switch (marker.className) {
      'motorcycle' => [
        ...box(2.2, .45, .45, 0, .35, 0),
        ...box(.9, .45, .55, 0, .75, 0),
        ...box(.28, .5, .85, -1.0, .25, 0),
        ...box(.28, .5, .85, 1.0, .25, 0),
      ],
      'bicycle' => [
        ...box(2.0, .22, .25, 0, .55, 0),
        ...box(.22, .65, .55, -.8, .35, 0),
        ...box(.22, .65, .55, .8, .35, 0),
      ],
      'bus' => box(4.3, 1.45, 1.25, 0, .75, 0),
      'truck' => [
        ...box(2.8, 1.25, 1.25, .65, .65, 0),
        ...box(1.25, 1.05, 1.2, -1.35, .55, 0),
      ],
      _ => [
        ...box(3.0, .85, 1.35, 0, .48, 0),
        ...box(1.65, .65, 1.12, .15, 1.15, 0),
      ],
    };
  }

  List<_SceneFace> _cuboid(
    _ScenePoint center,
    double width,
    double height,
    double depth,
    Color top,
    Color side,
  ) {
    final x = width / 2, y = height / 2, z = depth / 2;
    final lower = <_ScenePoint>[
      _ScenePoint(center.x - x, center.y - y, center.z - z),
      _ScenePoint(center.x + x, center.y - y, center.z - z),
      _ScenePoint(center.x + x, center.y - y, center.z + z),
      _ScenePoint(center.x - x, center.y - y, center.z + z),
    ];
    final upper = lower
        .map((p) => _ScenePoint(p.x, p.y + height, p.z))
        .toList();
    return _prism(upper, lower, top, side);
  }

  List<_SceneFace> _prism(
    List<_ScenePoint> top,
    List<_ScenePoint> bottom,
    Color topColor,
    Color sideColor,
  ) => [
    _SceneFace(top, topColor),
    for (var i = 0; i < top.length; i++)
      _SceneFace([
        top[i],
        top[(i + 1) % top.length],
        bottom[(i + 1) % top.length],
        bottom[i],
      ], sideColor.withValues(alpha: .9)),
  ];
}

class _SceneCamera {
  const _SceneCamera({
    required this.target,
    required this.yaw,
    required this.pitch,
    required this.distance,
    required this.viewport,
  });
  final _ScenePoint target;
  final double yaw, pitch, distance;
  final Size viewport;
  _ProjectedPoint? project(_ScenePoint point) {
    final x = point.x - target.x,
        y = point.y - target.y,
        z = point.z - target.z;
    final cy = math.cos(yaw),
        sy = math.sin(yaw),
        cp = math.cos(pitch),
        sp = math.sin(pitch);
    final rx = x * cy - z * sy, rz = x * sy + z * cy;
    final ry = y * cp - rz * sp;
    final depth = y * sp + rz * cp + distance;
    if (depth <= .05) return null;
    final focal = viewport.shortestSide * .92;
    return _ProjectedPoint(
      Offset(
        viewport.width / 2 + rx * focal / depth,
        viewport.height / 2 - ry * focal / depth,
      ),
      depth,
    );
  }
}
