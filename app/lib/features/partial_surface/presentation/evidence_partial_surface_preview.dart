import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/iris_spacing.dart';
import '../../../core/widgets/iris_app_bar.dart';
import '../domain/evidence_partial_surface.dart';

/// Local inspection view for a persisted visible-only mesh.  It intentionally
/// does not place the mesh on a map: that requires a separate current explicit
/// TASK012B world alignment in the reconstruction scene.
class EvidencePartialSurfacePreview extends StatefulWidget {
  const EvidencePartialSurfacePreview({required this.meshes, super.key});
  final List<EvidencePartialSurfaceMesh> meshes;

  @override
  State<EvidencePartialSurfacePreview> createState() =>
      _EvidencePartialSurfacePreviewState();
}

class _EvidencePartialSurfacePreviewState
    extends State<EvidencePartialSurfacePreview> {
  double _yaw = .12, _pitch = -.18, _zoom = 1, _gestureZoom = 1;
  Offset _pan = Offset.zero;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: IrisAppBar(
      title: 'Visible Partial 3D Surface',
      actions: <Widget>[
        IconButton(
          tooltip: 'Reset view',
          onPressed: () => setState(() {
            _yaw = .12;
            _pitch = -.18;
            _zoom = 1;
            _gestureZoom = 1;
            _pan = Offset.zero;
          }),
          icon: const Icon(Icons.center_focus_strong),
        ),
      ],
    ),
    body: Column(
      children: <Widget>[
        Expanded(
          child: GestureDetector(
            onScaleStart: (_) => _gestureZoom = _zoom,
            onScaleUpdate: (details) => setState(() {
              if (details.pointerCount > 1) {
                _zoom = (_gestureZoom * details.scale).clamp(.35, 8);
                final candidate = _pan + details.focalPointDelta;
                _pan = Offset(
                  candidate.dx.clamp(-900, 900).toDouble(),
                  candidate.dy.clamp(-900, 900).toDouble(),
                );
              } else {
                _yaw += details.focalPointDelta.dx * .008;
                _pitch = (_pitch + details.focalPointDelta.dy * .006).clamp(
                  -1.35,
                  -.12,
                );
              }
            }),
            child: CustomPaint(
              painter: _EvidenceSurfacePainter(
                meshes: widget.meshes,
                yaw: _yaw,
                pitch: _pitch,
                zoom: _zoom,
                pan: _pan,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(IrisSpacing.md),
          child: Text(
            'Visible evidence surface only • original pixel colours • relative, uncalibrated depth • no hidden surfaces, dimensions, damage finding, or metric placement established.',
          ),
        ),
      ],
    ),
  );
}

class _EvidenceSurfacePainter extends CustomPainter {
  const _EvidenceSurfacePainter({
    required this.meshes,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.pan,
  });
  final List<EvidencePartialSurfaceMesh> meshes;
  final double yaw, pitch, zoom;
  final Offset pan;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xff141e27),
    );
    final vertices = meshes.expand((mesh) => mesh.vertices).toList();
    if (vertices.isEmpty) return;
    final frame = PartialSurfacePreviewFrame.fromVertices(vertices);
    final distance = frame.lateralSpan * 2.7 / zoom;
    _View view(PartialSurfaceVertex v) {
      // The artifact retains its inverse-depth projection coordinates for
      // aligned world composition.  A local evidence inspection instead uses
      // the stored, original-image UV footprint so a wide relative-depth range
      // cannot pull visible pixels apart into camera rays.  Z still comes from
      // the same genuine relative-depth sample and remains nonmetric.
      final x = v.u - frame.centerU;
      final y = v.v - frame.centerV;
      final z = (v.z - frame.centerZ) * frame.displayDepthScale;
      final rx = x * math.cos(yaw) - z * math.sin(yaw);
      final rz = x * math.sin(yaw) + z * math.cos(yaw);
      return _View(
        rx,
        y * math.cos(pitch) - rz * math.sin(pitch),
        y * math.sin(pitch) + rz * math.cos(pitch) + distance,
      );
    }

    Offset? project(_View v) {
      if (v.z < .02) return null;
      final focal = size.shortestSide * .95;
      return Offset(
        size.width / 2 + pan.dx + v.x * focal / v.z,
        size.height / 2 + pan.dy - v.y * focal / v.z,
      );
    }

    final faces = <_PreviewFace>[];
    for (final mesh in meshes) {
      final transformed = mesh.vertices.map(view).toList(growable: false);
      for (final triangle in mesh.triangles) {
        final a = transformed[triangle.a],
            b = transformed[triangle.b],
            c = transformed[triangle.c];
        final pa = project(a), pb = project(b), pc = project(c);
        if (pa == null || pb == null || pc == null) continue;
        final va = mesh.vertices[triangle.a],
            vb = mesh.vertices[triangle.b],
            vc = mesh.vertices[triangle.c];
        faces.add(
          _PreviewFace(
            Path()
              ..moveTo(pa.dx, pa.dy)
              ..lineTo(pb.dx, pb.dy)
              ..lineTo(pc.dx, pc.dy)
              ..close(),
            (a.z + b.z + c.z) / 3,
            _averageColour(va.argb, vb.argb, vc.argb),
          ),
        );
      }
    }
    faces.sort((a, b) => b.depth.compareTo(a.depth));
    for (final face in faces) {
      canvas.drawPath(
        face.path,
        Paint()
          ..color = face.colour
          ..isAntiAlias = false,
      );
    }
  }

  Color _averageColour(int a, int b, int c) => Color.fromARGB(
    ((a >>> 24) + (b >>> 24) + (c >>> 24)) ~/ 3,
    ((a >>> 16 & 255) + (b >>> 16 & 255) + (c >>> 16 & 255)) ~/ 3,
    ((a >>> 8 & 255) + (b >>> 8 & 255) + (c >>> 8 & 255)) ~/ 3,
    ((a & 255) + (b & 255) + (c & 255)) ~/ 3,
  );

  @override
  bool shouldRepaint(covariant _EvidenceSurfacePainter oldDelegate) =>
      meshes != oldDelegate.meshes ||
      yaw != oldDelegate.yaw ||
      pitch != oldDelegate.pitch ||
      zoom != oldDelegate.zoom ||
      pan != oldDelegate.pan;
}

/// Display-only fit parameters for a nonmetric visible-surface preview.
///
/// The stored vertex coordinates remain untouched.  The depth scale merely
/// prevents an arbitrary relative-depth range from making a genuine partial
/// surface unreadably small in its local inspection view.
@visibleForTesting
class PartialSurfacePreviewFrame {
  const PartialSurfacePreviewFrame({
    required this.centerU,
    required this.centerV,
    required this.centerZ,
    required this.lateralSpan,
    required this.displayDepthScale,
  });

  factory PartialSurfacePreviewFrame.fromVertices(
    Iterable<PartialSurfaceVertex> vertices,
  ) {
    final all = vertices.toList(growable: false);
    if (all.isEmpty) throw ArgumentError.value(vertices, 'vertices', 'empty');
    final minU = all.map((v) => v.u).reduce(math.min);
    final maxU = all.map((v) => v.u).reduce(math.max);
    final minV = all.map((v) => v.v).reduce(math.min);
    final maxV = all.map((v) => v.v).reduce(math.max);
    final minZ = all.map((v) => v.z).reduce(math.min);
    final maxZ = all.map((v) => v.z).reduce(math.max);
    final lateralSpan = math.max(.25, math.max(maxU - minU, maxV - minV));
    final depthSpan = maxZ - minZ;
    return PartialSurfacePreviewFrame(
      // Use the visible sampled surface centroid rather than a range midpoint.
      // This keeps the actual visible structure centred as the user orbits it.
      centerU: all.map((v) => v.u).reduce((a, b) => a + b) / all.length,
      centerV: all.map((v) => v.v).reduce((a, b) => a + b) / all.length,
      centerZ: all.map((v) => v.z).reduce((a, b) => a + b) / all.length,
      lateralSpan: lateralSpan,
      displayDepthScale: depthSpan > lateralSpan ? lateralSpan / depthSpan : 1,
    );
  }

  final double centerU;
  final double centerV;
  final double centerZ;
  final double lateralSpan;
  final double displayDepthScale;
}

class _View {
  const _View(this.x, this.y, this.z);
  final double x, y, z;
}

class _PreviewFace {
  const _PreviewFace(this.path, this.depth, this.colour);
  final Path path;
  final double depth;
  final Color colour;
}
