import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'scene_render_data.dart';

class ProjectedFace {
  const ProjectedFace(this.mesh, this.face, this.path, this.depth, this.order);
  final RenderMesh mesh;
  final RenderFace face;
  final Path path;
  final double depth;
  final int order;
}

List<ProjectedFace> projectFaces(
  SceneRenderData data,
  SceneCamera camera,
  bool environment,
) {
  final faces = <ProjectedFace>[];
  var order = 0;
  for (final mesh in data.meshes) {
    if (!environment && mesh.id.startsWith('environment/')) continue;
    for (final face in mesh.faces) {
      final vertices = camera.clipVisible(face.vertices);
      if (vertices.length < 3) continue;
      final path = Path()..fillType = PathFillType.evenOdd;
      void ring(List<RenderPoint> points) {
        if (points.length < 3) return;
        final first = camera.screen(points.first);
        path.moveTo(first.dx, first.dy);
        for (final point in points.skip(1)) {
          final p = camera.screen(point);
          path.lineTo(p.dx, p.dy);
        }
        path.close();
      }

      ring(vertices);
      for (final hole in face.holes) {
        ring(camera.clipVisible(hole));
      }
      if (!path.getBounds().overlaps(Offset.zero & camera.viewport)) continue;
      faces.add(
        ProjectedFace(
          mesh,
          face,
          path,
          vertices.map((p) => p.z).reduce((a, b) => a + b) / vertices.length,
          order++,
        ),
      );
    }
  }
  faces.sort((a, b) {
    final depth = b.depth.compareTo(a.depth);
    return depth == 0 ? a.order.compareTo(b.order) : depth;
  });
  return faces;
}

/// Lighting is visualization only; never overwrite a source/base appearance.
Color shadeDisplayFace(RenderFace face) {
  if (face.vertices.length < 3) return face.color;
  final a = face.vertices[0], b = face.vertices[1], c = face.vertices[2];
  final ux = b.x - a.x, uy = b.y - a.y, uz = b.z - a.z;
  final vx = c.x - a.x, vy = c.y - a.y, vz = c.z - a.z;
  var nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
  final l = math.sqrt(nx * nx + ny * ny + nz * nz);
  if (!l.isFinite || l < 1e-9) return face.color;
  nx /= l;
  ny /= l;
  nz /= l;
  // Horizontal roofs are two-sided render surfaces; winding is not sun data.
  if (ny < -.8) {
    nx = -nx;
    ny = -ny;
    nz = -nz;
  }
  final light = (.68 + .32 * math.max(0, nx * -.35 + ny * .82 + nz * .45))
      .clamp(0.0, 1.0);
  return Color.lerp(Colors.black, face.color, light)!;
}

/// The reference plane is not an occluding terrain measurement. Roads are
/// coplanar map underlays. Draw both before volumes, preventing coarse painter
/// centroids from erasing parts of the road or building bases with a ground tile.
/// Solid faces keep camera-space far-to-near ordering within their group.
List<ProjectedFace> scenePaintOrder(List<ProjectedFace> faces) => [
  ...faces.where((f) => f.mesh.id == 'reference-ground'),
  ...faces.where((f) => f.mesh.id.startsWith('road/')),
  ...faces.where(
    (f) => f.mesh.id != 'reference-ground' && !f.mesh.id.startsWith('road/'),
  ),
];

class ReconstructionPainter extends CustomPainter {
  ReconstructionPainter({
    required this.data,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.pan,
    required this.evidence,
    required this.centerlines,
    required this.grid,
    required this.environment,
  });
  final SceneRenderData data;
  final double yaw, pitch, zoom;
  final Offset pan;
  final bool evidence, centerlines, grid, environment;
  List<ProjectedFace> _faces = const [];
  bool _evidenceAnchorInViewport = false;
  int get visibleRoadFaces =>
      _faces.where((f) => f.mesh.id.startsWith('road/')).length;
  int get visibleRoadTopFaces => _faces
      .where(
        (f) =>
            f.mesh.id.startsWith('road/') &&
            f.face.vertices.every((p) => (p.y - .14).abs() < .0001),
      )
      .length;
  int get submittedRoadFaces => data.roadDiagnostics.renderFaces;
  bool get evidenceAnchorInViewport => _evidenceAnchorInViewport;
  RenderMesh? objectAt(Offset position) {
    for (final face in _faces.reversed) {
      if (face.path.contains(position)) return face.mesh;
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xff141e27),
    );
    final target = data.frame.target;
    final camera = SceneCamera(
      target: RenderPoint(target.x + pan.dx, target.y, target.z + pan.dy),
      yaw: yaw,
      pitch: pitch,
      distance: data.frame.span * 1.35 / zoom,
      viewport: size,
    );
    _faces = scenePaintOrder(projectFaces(data, camera, environment));
    final viewport = Offset.zero & size;
    _evidenceAnchorInViewport = data.source.vehicles.any((vehicle) {
      final point = vehicle.anchor.worldAnchor;
      final projected = camera.project(RenderPoint(point.x, point.y, point.z));
      return projected != null && viewport.contains(projected);
    });
    final points = evidence
        ? data.source.alignedPoints
              .map((p) => camera.view(RenderPoint(p.x, p.y, p.z)))
              .where((p) => p.z >= .1)
              .toList()
        : <RenderPoint>[];
    points.sort((a, b) => b.z.compareTo(a.z));
    var pointIndex = 0;
    void drawPoint(RenderPoint p) => canvas.drawCircle(
      camera.screen(p),
      1.4,
      Paint()..color = const Color(0xff73d7e8),
    );
    for (final projected in _faces) {
      final underlay =
          projected.mesh.id == 'reference-ground' ||
          projected.mesh.id.startsWith('road/');
      while (!underlay &&
          pointIndex < points.length &&
          points[pointIndex].z > projected.depth) {
        drawPoint(points[pointIndex++]);
      }
      canvas.drawPath(
        projected.path,
        Paint()
          ..isAntiAlias =
              false // Shared coplanar subdivisions must not show seams.
          ..color = projected.face.preserveSourceColour
              ? projected.face.color
              : shadeDisplayFace(projected.face),
      );
      if (projected.mesh.id.startsWith('road/')) {
        // Display-only surface separation, not a curb/lane/map attribute.
        canvas.drawPath(
          projected.path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = .7
            ..isAntiAlias = true
            ..color = const Color(0x66798a94),
        );
      }
      final outlined =
          projected.mesh.id.startsWith('environment/') ||
          projected.mesh.id.contains('/detection/');
      if (outlined) {
        canvas.drawPath(
          projected.path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = .65
            ..isAntiAlias = true
            ..color = const Color(0x3d0b1116),
        );
      }
    }
    while (pointIndex < points.length) {
      drawPoint(points[pointIndex++]);
    }
    void line(RenderPoint a, RenderPoint b, Color color) {
      final pa = camera.project(a), pb = camera.project(b);
      if (pa != null && pb != null) {
        canvas.drawLine(
          pa,
          pb,
          Paint()
            ..color = color
            ..strokeWidth = 1,
        );
      }
    }

    // Intentionally x-ray technical overlays, enabled only on demand.
    if (grid) {
      for (var i = -10; i <= 10; i++) {
        line(
          RenderPoint(target.x + i * 5, .14, target.z - 50),
          RenderPoint(target.x + i * 5, .14, target.z + 50),
          Colors.white12,
        );
        line(
          RenderPoint(target.x - 50, .14, target.z + i * 5),
          RenderPoint(target.x + 50, .14, target.z + i * 5),
          Colors.white12,
        );
      }
    }
    if (centerlines) {
      for (final road in data.source.roads?.roads ?? []) {
        for (var i = 1; i < road.localCoordinates.length; i++) {
          final a = road.localCoordinates[i - 1], b = road.localCoordinates[i];
          line(
            RenderPoint(a[0], .15, a[1]),
            RenderPoint(b[0], .15, b[1]),
            const Color(0xffc9ac6d),
          );
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ReconstructionPainter old) =>
      data != old.data ||
      yaw != old.yaw ||
      pitch != old.pitch ||
      zoom != old.zoom ||
      pan != old.pan ||
      evidence != old.evidence ||
      centerlines != old.centerlines ||
      grid != old.grid ||
      environment != old.environment;
}
