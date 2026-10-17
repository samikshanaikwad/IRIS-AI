import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/domain/case_local_world.dart';
import '../../geometry/domain/relative_geometry.dart';
import '../domain/reconstruction_scene.dart';

/// DISPLAY ONLY. These mesh dimensions must never be passed to analytical or
/// future physics code. Source facts live in ReconstructionScene, separately.
class RenderPoint {
  const RenderPoint(this.x, this.y, this.z);
  final double x, y, z;
}

class RenderFace {
  const RenderFace(
    this.vertices,
    this.color, {
    this.holes = const [],
    this.preserveSourceColour = false,
  });
  final List<RenderPoint> vertices;
  final List<List<RenderPoint>> holes;
  final Color color;

  /// Evidence-photo colours are already observations rather than display
  /// materials. Keep them out of directional display shading.
  final bool preserveSourceColour;
}

class RenderMesh {
  const RenderMesh(this.id, this.label, this.provenance, this.faces);
  final String id, label, provenance;
  final List<RenderFace> faces;
}

/// Count-only rendering diagnostics. No coordinates or source payloads are
/// exposed; this exists to prove the real TASK011 road survives each stage.
class RoadRenderDiagnostics {
  const RoadRenderDiagnostics({
    required this.sourceRoads,
    required this.centerlineSegments,
    required this.ribbonPieces,
    required this.renderFaces,
    required this.explicitWidths,
    required this.representationalWidths,
    required this.nearestEvidenceBucket,
    required this.nearestAlignedGeometryBucket,
  });
  final int sourceRoads;
  final int centerlineSegments;
  final int ribbonPieces;
  final int renderFaces;
  final int explicitWidths;
  final int representationalWidths;
  final String nearestEvidenceBucket;
  final String nearestAlignedGeometryBucket;

  String get safeSummary =>
      'roads=$sourceRoads segments=$centerlineSegments ribbons=$ribbonPieces '
      'faces=$renderFaces widthsExplicit=$explicitWidths '
      'widthsRepresentational=$representationalWidths '
      'nearestEvidence=$nearestEvidenceBucket '
      'nearestAlignedGeometry=$nearestAlignedGeometryBucket '
      'canonicalFrame=ready';
}

class SceneFrame {
  const SceneFrame(this.target, this.span, {this.yaw = .5, this.pitch = -.72});
  final RenderPoint target;
  final double span, yaw, pitch;
  factory SceneFrame.forScene(ReconstructionScene scene) {
    // Camera framing is display-only: prioritize real vehicle anchors, not the
    // distant relative-depth tail or the whole provider query radius.
    final anchors = scene.vehicles
        .map(
          (v) => RenderPoint(
            v.anchor.worldAnchor.x,
            v.anchor.worldAnchor.y,
            v.anchor.worldAnchor.z,
          ),
        )
        .toList();
    if (anchors.isEmpty) {
      return _unobstructed(scene, const RenderPoint(0, 0, 0), 65);
    }
    final xs = anchors.map((p) => p.x),
        zs = anchors.map((p) => p.z),
        ys = anchors.map((p) => p.y);
    final minX = xs.reduce(math.min),
        maxX = xs.reduce(math.max),
        minZ = zs.reduce(math.min),
        maxZ = zs.reduce(math.max);
    final incident = RenderPoint(
      (minX + maxX) / 2,
      (ys.reduce(math.min) + ys.reduce(math.max)) / 2,
      (minZ + maxZ) / 2,
    );
    var target = incident;
    var span = (math.max(maxX - minX, maxZ - minZ) * 1.8 + 18).clamp(
      18.0,
      72.0,
    );
    // Include the nearest genuine road segment within the incident vicinity.
    // This changes only the viewing target, never the evidence anchor.
    var nearestDistance = 40.0;
    RenderPoint? nearest;
    List<double>? nearestA, nearestB;
    for (final road in scene.roads?.roads ?? []) {
      for (var i = 1; i < road.localCoordinates.length; i++) {
        final a = road.localCoordinates[i - 1], b = road.localCoordinates[i];
        final dx = b[0] - a[0], dz = b[1] - a[1], l2 = dx * dx + dz * dz;
        if (l2 == 0) continue;
        final t = (((incident.x - a[0]) * dx + (incident.z - a[1]) * dz) / l2)
            .clamp(0.0, 1.0);
        final x = a[0] + t * dx, z = a[1] + t * dz;
        final distance = math.sqrt(
          math.pow(x - incident.x, 2) + math.pow(z - incident.z, 2),
        );
        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearest = RenderPoint(x, 0, z);
          nearestA = a;
          nearestB = b;
        }
      }
    }
    if (nearest != null) {
      target = RenderPoint(
        incident.x + (nearest.x - incident.x) * .18,
        incident.y,
        incident.z + (nearest.z - incident.z) * .18,
      );
      // A nearby road informs composition, but the provider radius must not
      // make one evidence vehicle microscopic. Wider context remains reachable
      // by zooming out.
      final roadA = nearestA, roadB = nearestB;
      if (roadA != null && roadB != null) {
        final dx = roadB[0] - roadA[0];
        final dz = roadB[1] - roadA[1];
        final length = math.sqrt(dx * dx + dz * dz);
        // Reserve a useful, bounded amount of genuine road around the incident.
        // This extends only the display frame; it creates no road coordinates.
        final usefulRoad = math.min(22.0, length);
        span = math.max(span, nearestDistance + usefulRoad).clamp(18.0, 72.0);
      }
    }
    // Bias the display look target slightly below the analytical anchor so the
    // useful scene occupies more of the viewport and empty sky is reduced.
    target = RenderPoint(target.x, incident.y - span * .065, target.z);
    return _unobstructed(scene, target, span);
  }

  static SceneFrame _unobstructed(
    ReconstructionScene scene,
    RenderPoint target,
    double span,
  ) {
    final buildings = scene.environmentFeatures
        .where((f) => f.featureType == 'building')
        .toList();
    var best = SceneFrame(target, span), bestScore = double.infinity;
    final incident = scene.vehicles.isEmpty
        ? target
        : RenderPoint(
            scene.vehicles
                    .map((v) => v.anchor.worldAnchor.x)
                    .reduce((a, b) => a + b) /
                scene.vehicles.length,
            scene.vehicles
                    .map((v) => v.anchor.worldAnchor.y)
                    .reduce((a, b) => a + b) /
                scene.vehicles.length,
            scene.vehicles
                    .map((v) => v.anchor.worldAnchor.z)
                    .reduce((a, b) => a + b) /
                scene.vehicles.length,
          );
    // Bounded deterministic display-camera search. It scores the projected
    // incident composition; no evidence or source geometry is moved/removed.
    for (final pitch in [-.62, -.76, -.9]) {
      for (var i = 0; i < 16; i++) {
        final yaw = .35 + i * math.pi / 8;
        final candidate = SceneFrame(target, span, yaw: yaw, pitch: pitch);
        final eye = candidate.eye;
        final camera = SceneCamera(
          target: target,
          yaw: yaw,
          pitch: pitch,
          distance: span * 1.35,
          viewport: const Size(1000, 700),
        );
        final incidentScreen = camera.project(incident);
        var score = i * .001 + (pitch + .72).abs() * 2;
        if (incidentScreen == null) {
          score += 100000;
        } else {
          // Keep evidence in the useful central region, leaving context around
          // it. This is screen composition, not an inferred incident position.
          final dx = (incidentScreen.dx - 500) / 500;
          final dy = (incidentScreen.dy - 385) / 350;
          score += (dx * dx * 180) + (dy * dy * 120);
          if (incidentScreen.dx < 180 ||
              incidentScreen.dx > 820 ||
              incidentScreen.dy < 135 ||
              incidentScreen.dy > 620) {
            score += 800;
          }
        }
        for (final b in buildings) {
          final height = b.sourceHeight ?? 6;
          bool inside(double x, double z) =>
              insideFootprint(x, z, b.localCoordinates) &&
              !b.localHoles.any((r) => insideFootprint(x, z, r));
          if (eye.y <= height + 3 &&
              (inside(eye.x, eye.z) ||
                  nearFootprint(eye.x, eye.z, b.localCoordinates, 3))) {
            score += 10000;
          }
          for (var step = 1; step < 32; step++) {
            final t = step / 32;
            final y = eye.y + (target.y - eye.y) * t;
            if (y >= 0 &&
                y <= height + .5 &&
                inside(
                  eye.x + (target.x - eye.x) * t,
                  eye.z + (target.z - eye.z) * t,
                )) {
              score += 100;
              break;
            }
          }
          final bounds = projectedBuildingBounds(
            camera,
            b.localCoordinates,
            height,
          );
          if (bounds != null) {
            final clipped = bounds.intersect(
              const Rect.fromLTWH(0, 0, 1000, 700),
            );
            if (!clipped.isEmpty) {
              final areaFraction = clipped.width * clipped.height / 700000;
              final center = clipped.intersect(
                const Rect.fromLTWH(220, 105, 560, 500),
              );
              score += areaFraction * 1800;
              score += center.width * center.height / 700000 * 2600;
              if (incidentScreen != null &&
                  clipped.inflate(5).contains(incidentScreen)) {
                score += 12000;
              }
            }
          }
        }
        // Prefer a candidate that visibly explains the evidence in relation to
        // genuine nearby road geometry. Only source road segments contribute.
        score -= visibleNearbyRoadScore(camera, scene, incident) * 3.5;
        if (score < bestScore) {
          best = candidate;
          bestScore = score;
        }
      }
    }
    if (bestScore >= 10000 && buildings.isNotEmpty) {
      // If every bounded orbit is enclosed, place the initial eye above the
      // rendered volumes rather than inside a wall. This is a display fallback.
      final highest = buildings
          .map((b) => b.sourceHeight ?? 6.0)
          .reduce(math.max);
      final elevatedSpan = math.max(
        span,
        (highest + 8 - target.y) / (1.35 * math.sin(1.25)),
      );
      if (elevatedSpan.isFinite) {
        return SceneFrame(target, elevatedSpan, yaw: best.yaw, pitch: -.9);
      }
    }
    return best;
  }

  RenderPoint get eye => RenderPoint(
    target.x - span * 1.35 * math.cos(pitch) * math.sin(yaw),
    target.y - span * 1.35 * math.sin(pitch),
    target.z - span * 1.35 * math.cos(pitch) * math.cos(yaw),
  );
}

Rect? projectedBuildingBounds(
  SceneCamera camera,
  List<List<double>> ring,
  double height,
) {
  final points = <Offset>[];
  for (final p in ring) {
    for (final y in [0.0, height]) {
      final q = camera.project(RenderPoint(p[0], y, p[1]));
      if (q != null && q.dx.isFinite && q.dy.isFinite) points.add(q);
    }
  }
  if (points.length < 3) return null;
  final xs = points.map((p) => p.dx), ys = points.map((p) => p.dy);
  return Rect.fromLTRB(
    xs.reduce(math.min),
    ys.reduce(math.min),
    xs.reduce(math.max),
    ys.reduce(math.max),
  );
}

double visibleNearbyRoadScore(
  SceneCamera camera,
  ReconstructionScene scene,
  RenderPoint incident,
) {
  var score = 0.0;
  for (final road in scene.roads?.roads ?? []) {
    for (var i = 1; i < road.localCoordinates.length; i++) {
      final a = road.localCoordinates[i - 1], b = road.localCoordinates[i];
      final mx = (a[0] + b[0]) / 2, mz = (a[1] + b[1]) / 2;
      if (math.sqrt(
            math.pow(mx - incident.x, 2) + math.pow(mz - incident.z, 2),
          ) >
          55) {
        continue;
      }
      final pa = camera.project(RenderPoint(a[0], .05, a[1]));
      final pb = camera.project(RenderPoint(b[0], .05, b[1]));
      if (pa == null || pb == null) continue;
      final viewport = Offset.zero & camera.viewport;
      if (!viewport.inflate(30).contains(pa) &&
          !viewport.inflate(30).contains(pb)) {
        continue;
      }
      score += math.min(20, (pa - pb).distance / 18);
    }
  }
  return score;
}

bool insideFootprint(double x, double z, List<List<double>> ring) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final a = ring[i], b = ring[j];
    if ((a[1] > z) != (b[1] > z) &&
        x < (b[0] - a[0]) * (z - a[1]) / (b[1] - a[1]) + a[0]) {
      inside = !inside;
    }
  }
  return inside;
}

bool nearFootprint(double x, double z, List<List<double>> ring, double margin) {
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i], b = ring[(i + 1) % ring.length];
    final dx = b[0] - a[0], dz = b[1] - a[1], l2 = dx * dx + dz * dz;
    final t = l2 == 0 ? 0.0 : ((x - a[0]) * dx + (z - a[1]) * dz) / l2;
    final u = t.clamp(0.0, 1.0);
    if (math.pow(x - a[0] - u * dx, 2) + math.pow(z - a[1] - u * dz, 2) <
        margin * margin) {
      return true;
    }
  }
  return false;
}

class SceneCamera {
  const SceneCamera({
    required this.target,
    required this.yaw,
    required this.pitch,
    required this.distance,
    required this.viewport,
  });
  final RenderPoint target;
  final double yaw, pitch, distance;
  final Size viewport;
  bool get valid =>
      [
        target.x,
        target.y,
        target.z,
        yaw,
        pitch,
        distance,
        viewport.width,
        viewport.height,
      ].every((v) => v.isFinite) &&
      distance > 0 &&
      viewport.width > 0 &&
      viewport.height > 0;
  RenderPoint view(RenderPoint p) {
    final x = p.x - target.x, y = p.y - target.y, z = p.z - target.z;
    final rx = x * math.cos(yaw) - z * math.sin(yaw),
        rz = x * math.sin(yaw) + z * math.cos(yaw);
    return RenderPoint(
      rx,
      y * math.cos(pitch) - rz * math.sin(pitch),
      y * math.sin(pitch) + rz * math.cos(pitch) + distance,
    );
  }

  Offset screen(RenderPoint cameraPoint) =>
      !valid ||
          ![
            cameraPoint.x,
            cameraPoint.y,
            cameraPoint.z,
          ].every((v) => v.isFinite) ||
          cameraPoint.z < .099999
      ? Offset.zero
      : Offset(
          viewport.width / 2 +
              cameraPoint.x * viewport.shortestSide * .95 / cameraPoint.z,
          viewport.height / 2 -
              cameraPoint.y * viewport.shortestSide * .95 / cameraPoint.z,
        );
  Offset? project(RenderPoint p) {
    if (!valid || ![p.x, p.y, p.z].every((v) => v.isFinite)) return null;
    final v = view(p);
    return v.z < .1 ? null : screen(v);
  }

  List<RenderPoint> clipNear(List<RenderPoint> world) {
    if (!valid || world.any((p) => ![p.x, p.y, p.z].every((v) => v.isFinite))) {
      return [];
    }
    final input = world.map(view).toList(), output = <RenderPoint>[];
    if (input.isEmpty) return output;
    var a = input.last;
    for (final b in input) {
      if ((a.z >= .1) != (b.z >= .1)) {
        final t = (.1 - a.z) / (b.z - a.z);
        output.add(
          RenderPoint(a.x + t * (b.x - a.x), a.y + t * (b.y - a.y), .1),
        );
      }
      if (b.z >= .1) output.add(b);
      a = b;
    }
    return output;
  }

  /// Clip in camera space to all viewport planes as well as the near plane.
  /// Keeps projected paths bounded even when a user orbits through a building.
  List<RenderPoint> clipVisible(List<RenderPoint> world) {
    var points = clipNear(world);
    final focal = viewport.shortestSide * .95;
    if (!valid || focal <= 0) return [];
    final sx = viewport.width / (2 * focal), sy = viewport.height / (2 * focal);
    for (final plane in <double Function(RenderPoint)>[
      (p) => p.x + p.z * sx,
      (p) => p.z * sx - p.x,
      (p) => p.y + p.z * sy,
      (p) => p.z * sy - p.y,
    ]) {
      if (points.isEmpty) return [];
      final output = <RenderPoint>[];
      var a = points.last;
      for (final b in points) {
        final da = plane(a), db = plane(b);
        if ((da >= 0) != (db >= 0)) {
          final t = da / (da - db);
          output.add(
            RenderPoint(
              a.x + t * (b.x - a.x),
              a.y + t * (b.y - a.y),
              a.z + t * (b.z - a.z),
            ),
          );
        }
        if (db >= 0) output.add(b);
        a = b;
      }
      points = output;
    }
    return points;
  }
}

String _nearestRoadBucket(ReconstructionScene scene) {
  final anchors = scene.vehicles.map((v) => v.anchor.worldAnchor).toList();
  if (anchors.isEmpty) return 'noEvidenceAnchor';
  var nearest = double.infinity;
  for (final anchor in anchors) {
    nearest = math.min(
      nearest,
      nearestMapPolylineDistance(
        CaseLocalWorldPoint(xEast: anchor.x, yUp: anchor.y, zNorth: anchor.z),
        (scene.roads?.roads ?? []).map((r) => r.localCoordinates),
      ),
    );
  }
  return mapDistanceBucket(nearest);
}

String _nearestAlignedGeometryRoadBucket(ReconstructionScene scene) {
  final points = scene.alignedPoints.toList();
  if (points.isEmpty) return 'noAlignedGeometry';
  var nearest = double.infinity;
  final polylines = (scene.roads?.roads ?? [])
      .map((r) => r.localCoordinates)
      .toList();
  for (final point in points) {
    nearest = math.min(
      nearest,
      nearestMapPolylineDistance(
        CaseLocalWorldPoint(xEast: point.x, yUp: point.y, zNorth: point.z),
        polylines,
      ),
    );
  }
  return mapDistanceBucket(nearest);
}

class SceneRenderData {
  SceneRenderData(this.source) : frame = SceneFrame.forScene(source) {
    meshes = _build();
  }
  final ReconstructionScene source;
  final SceneFrame frame;
  late final RoadRenderDiagnostics roadDiagnostics;
  late final List<RenderMesh> meshes;
  List<RenderMesh> _build() {
    final out = <RenderMesh>[];
    final groundFaces = <RenderFace>[];
    // Small tiles improve painter depth ordering; this is a neutral reference
    // platform, not evidence of ground elevation/surface or a mapped land area.
    // Keep the display platform local to the incident composition. It is not
    // the provider radius and does not claim mapped terrain extent.
    final extent = (frame.span * .62).clamp(12.0, 38.0), step = extent / 5;
    for (var i = -5; i < 5; i++) {
      for (var j = -5; j < 5; j++) {
        final x = frame.target.x + i * step, z = frame.target.z + j * step;
        groundFaces.add(
          RenderFace([
            RenderPoint(x, -.05, z),
            RenderPoint(x + step, -.05, z),
            RenderPoint(x + step, -.05, z + step),
            RenderPoint(x, -.05, z + step),
          ], const Color(0xff3e4a4f)),
        );
      }
    }
    final rim = [
      RenderPoint(frame.target.x - extent, -.05, frame.target.z - extent),
      RenderPoint(frame.target.x + extent, -.05, frame.target.z - extent),
      RenderPoint(frame.target.x + extent, -.05, frame.target.z + extent),
      RenderPoint(frame.target.x - extent, -.05, frame.target.z + extent),
    ];
    groundFaces.addAll(
      renderPrism(
        rim,
        rim.map((p) => RenderPoint(p.x, -.25, p.z)).toList(),
        const Color(0xff3e4a4f),
      ).skip(1),
    );
    out.add(
      RenderMesh(
        'reference-ground',
        'Reference ground',
        'Visualization only • Terrain elevation not established',
        groundFaces,
      ),
    );
    var centerlineSegments = 0,
        ribbonPieces = 0,
        roadFaces = 0,
        explicitWidths = 0,
        representationalWidths = 0;
    for (final road in source.roads?.roads ?? []) {
      final width =
          road.width != null && road.width!.isFinite && road.width! > 0
          ? road.width!
          : null;
      if (width == null) {
        representationalWidths++;
      } else {
        explicitWidths++;
      }
      final faces = <RenderFace>[];
      for (var i = 1; i < road.localCoordinates.length; i++) {
        centerlineSegments++;
        final a = CaseLocalWorldPoint.fromMapXZ(road.localCoordinates[i - 1]),
            b = CaseLocalWorldPoint.fromMapXZ(road.localCoordinates[i]);
        final length = math.sqrt(
          math.pow(b.xEast - a.xEast, 2) + math.pow(b.zNorth - a.zNorth, 2),
        );
        final pieces = math.max(1, (length / 8).ceil());
        ribbonPieces += pieces;
        for (var k = 0; k < pieces; k++) {
          faces.addAll(
            renderSlab(
              a.xEast + (b.xEast - a.xEast) * k / pieces,
              a.zNorth + (b.zNorth - a.zNorth) * k / pieces,
              a.xEast + (b.xEast - a.xEast) * (k + 1) / pieces,
              a.zNorth + (b.zNorth - a.zNorth) * (k + 1) / pieces,
              width ?? 5.0,
              .14,
              -.08,
              const Color(0xff182832),
            ),
          );
        }
      }
      roadFaces += faces.length;
      out.add(
        RenderMesh(
          'road/${road.id}',
          road.name ?? 'Mapped road',
          'Centerline: OpenStreetMap • ${width == null ? 'Surface width: representational / unknown' : 'Width: explicit map attribute'} • Thickness: display only',
          faces,
        ),
      );
    }
    roadDiagnostics = RoadRenderDiagnostics(
      sourceRoads: source.roads?.roads.length ?? 0,
      centerlineSegments: centerlineSegments,
      ribbonPieces: ribbonPieces,
      renderFaces: roadFaces,
      explicitWidths: explicitWidths,
      representationalWidths: representationalWidths,
      nearestEvidenceBucket: _nearestRoadBucket(source),
      nearestAlignedGeometryBucket: _nearestAlignedGeometryRoadBucket(source),
    );
    for (final feature in source.environmentFeatures) {
      final faces = <RenderFace>[];
      var appearance = 'Display dimensions representational';
      if (feature.featureType == 'building' &&
          feature.localCoordinates.length >= 3) {
        final height = feature.sourceHeight ?? 6.0;
        // Unknown appearance remains provenance-unknown. These neutral base
        // tones are deterministic display materials, not source colors.
        final wall = Color(feature.wallAppearance.argb ?? 0xffaeb5b5);
        final roof = Color(feature.roofAppearance.argb ?? 0xffc8cdcb);
        final ring = displayFootprint(feature.localCoordinates);
        final top = ring.map((p) => RenderPoint(p[0], height, p[1])).toList();
        final bottom = ring.map((p) => RenderPoint(p[0], 0, p[1])).toList();
        faces.addAll(
          renderPrism(
            top,
            bottom,
            wall,
            roofColor: roof,
            subdivideWalls: true,
            holes: feature.localHoles
                .map(
                  (r) => displayFootprint(
                    r,
                    hole: true,
                  ).map((p) => RenderPoint(p[0], height, p[1])).toList(),
                )
                .toList(),
          ),
        );
        for (final original in feature.localHoles) {
          final ring = displayFootprint(original, hole: true);
          final innerTop = ring
              .map((p) => RenderPoint(p[0], height, p[1]))
              .toList();
          final innerBottom = ring
              .map((p) => RenderPoint(p[0], 0, p[1]))
              .toList();
          faces.addAll(
            renderPrism(
              innerTop,
              innerBottom,
              wall,
              subdivideWalls: true,
            ).skip(1),
          );
        }
        appearance = feature.sourceHeight == null
            ? 'Height: representational — source height unavailable'
            : 'Height: map-derived source attribute';
        appearance +=
            '\nWall appearance: ${feature.wallAppearance.label}\nRoof appearance: ${feature.roofAppearance.label}'
            '\nDisplay lighting only • Roof form not established';
      } else if (feature.featureType == 'tree' &&
          feature.localCoordinates.isNotEmpty) {
        final p = CaseLocalWorldPoint.fromMapXZ(feature.localCoordinates.first);
        faces.addAll(
          renderBox(
            RenderPoint(p.xEast, 1.4, p.zNorth),
            .35,
            2.8,
            .35,
            const Color(0xff75634e),
          ),
        );
        faces.addAll(
          renderBox(
            RenderPoint(p.xEast, 3.2, p.zNorth),
            2.0,
            2.2,
            2.0,
            const Color(0xff527362),
          ),
        );
      } else if (feature.featureType == 'barrier') {
        for (var i = 1; i < feature.localCoordinates.length; i++) {
          final a = CaseLocalWorldPoint.fromMapXZ(
                feature.localCoordinates[i - 1],
              ),
              b = CaseLocalWorldPoint.fromMapXZ(feature.localCoordinates[i]);
          faces.addAll(
            renderSlab(
              a.xEast,
              a.zNorth,
              b.xEast,
              b.zNorth,
              .2,
              1.2,
              0,
              const Color(0xff85817a),
            ),
          );
        }
      }
      if (faces.isNotEmpty) {
        out.add(
          RenderMesh(
            'environment/${feature.id}',
            'Mapped ${feature.featureType}',
            '${feature.provider} • ${feature.sourceId ?? feature.id}\n'
                '$appearance\nGeometry: map-derived${feature.sourceRelease == null ? '' : ' • release ${feature.sourceRelease}'}',
            faces,
          ),
        );
      }
    }
    final partialVehicleIds = <String>{};
    for (final surface in source.partialSurfaces) {
      final local = surface.mesh.vertices;
      final world = local
          .map((vertex) {
            final point = surface.alignment.transform(
              RelativePoint(
                x: vertex.x,
                y: vertex.y,
                z: vertex.z,
                u: vertex.u,
                v: vertex.v,
              ),
            );
            return RenderPoint(point.x, point.y, point.z);
          })
          .toList(growable: false);
      final faces = <RenderFace>[];
      for (final triangle in surface.mesh.triangles) {
        if (triangle.a >= world.length ||
            triangle.b >= world.length ||
            triangle.c >= world.length) {
          continue;
        }
        faces.add(
          RenderFace(
            <RenderPoint>[
              world[triangle.a],
              world[triangle.b],
              world[triangle.c],
            ],
            _surfaceFaceColour(
              local[triangle.a].argb,
              local[triangle.b].argb,
              local[triangle.c].argb,
            ),
            preserveSourceColour: true,
          ),
        );
      }
      if (faces.isEmpty) continue;
      partialVehicleIds.add(surface.vehicleId);
      out.add(
        RenderMesh(
          'evidence-surface/${surface.vehicleId}',
          'Evidence-coloured partial ${surface.mesh.part.className}',
          'Visible pixels: original evidence colour + current vehicle mask + relative depth\n'
              'Evidence-derived + user aligned • partial, nonmetric, uncalibrated\n'
              'No hidden geometry, dimensions, damage finding, or orientation established',
          faces,
        ),
      );
    }
    for (final vehicle in source.vehicles) {
      // A current visible surface is preferable to the old class silhouette.
      // Never cover a real, potentially damaged appearance with an intact
      // representational proxy for the same evidence/detection.
      if (partialVehicleIds.contains(vehicle.id)) continue;
      out.add(
        RenderMesh(
          vehicle.id,
          vehicle.anchor.className,
          'Evidence: ${vehicle.evidenceId}\nDetection score: ${vehicle.anchor.score.toStringAsFixed(3)}\n'
          'Anchor: relative image geometry + user alignment\nRepresentational display proportions\nDimensions: not measured • Orientation: not established\n'
          'Bounding-box/background uncertainty; segmentation unavailable',
          // View-readable display size, not physical dimensions. Pivot remains
          // exactly the accepted anchor; never persisted or used analytically.
          vehicleFaces(vehicle)
              .map(
                (f) => RenderFace(
                  f.vertices.map((p) {
                    final a = vehicle.anchor.worldAnchor;
                    final s = (frame.span / 16).clamp(1.0, 3.0);
                    return RenderPoint(
                      a.x + (p.x - a.x) * s,
                      a.y + (p.y - a.y) * s,
                      a.z + (p.z - a.z) * s,
                    );
                  }).toList(),
                  f.color,
                ),
              )
              .toList(),
        ),
      );
    }
    out.add(
      RenderMesh(
        'incident-reference',
        ReconstructionScene.originLabel,
        'Confirmed incident map location • No collision point established',
        // Thin ground ring, a reference symbol rather than a physical object.
        [
          for (var i = 0; i < 24; i++)
            RenderFace([
              RenderPoint(
                .8 * math.cos(i * math.pi / 12),
                .16,
                .8 * math.sin(i * math.pi / 12),
              ),
              RenderPoint(
                .8 * math.cos((i + 1) * math.pi / 12),
                .16,
                .8 * math.sin((i + 1) * math.pi / 12),
              ),
              RenderPoint(
                .65 * math.cos((i + 1) * math.pi / 12),
                .16,
                .65 * math.sin((i + 1) * math.pi / 12),
              ),
              RenderPoint(
                .65 * math.cos(i * math.pi / 12),
                .16,
                .65 * math.sin(i * math.pi / 12),
              ),
            ], const Color(0xffc6a780)),
        ],
      ),
    );
    return List.unmodifiable(out);
  }
}

Color _surfaceFaceColour(int a, int b, int c) => Color.fromARGB(
  ((a >>> 24) + (b >>> 24) + (c >>> 24)) ~/ 3,
  (((a >>> 16) & 255) + ((b >>> 16) & 255) + ((c >>> 16) & 255)) ~/ 3,
  (((a >>> 8) & 255) + ((b >>> 8) & 255) + ((c >>> 8) & 255)) ~/ 3,
  ((a & 255) + (b & 255) + (c & 255)) ~/ 3,
);

/// Normalize winding and repeated closure for display only, retaining the
/// original source geometry. Interior rings face into the courtyard.
List<List<double>> displayFootprint(
  List<List<double>> source, {
  bool hole = false,
}) {
  final ring = <List<double>>[];
  for (final p in source) {
    final canonical = CaseLocalWorldPoint.fromMapXZ(p).mapXZ;
    if (ring.isEmpty ||
        canonical[0] != ring.last[0] ||
        canonical[1] != ring.last[1]) {
      ring.add(canonical);
    }
  }
  if (ring.length > 1 &&
      ring.first[0] == ring.last[0] &&
      ring.first[1] == ring.last[1]) {
    ring.removeLast();
  }
  var area = 0.0;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i], b = ring[(i + 1) % ring.length];
    area += a[0] * b[1] - b[0] * a[1];
  }
  return (area < 0) != hole ? ring.reversed.toList() : ring;
}

List<RenderFace> renderBox(
  RenderPoint c,
  double w,
  double h,
  double d,
  Color color,
) {
  final bottom = [
    RenderPoint(c.x - w / 2, c.y - h / 2, c.z - d / 2),
    RenderPoint(c.x + w / 2, c.y - h / 2, c.z - d / 2),
    RenderPoint(c.x + w / 2, c.y - h / 2, c.z + d / 2),
    RenderPoint(c.x - w / 2, c.y - h / 2, c.z + d / 2),
  ];
  return renderPrism(
    bottom.map((p) => RenderPoint(p.x, p.y + h, p.z)).toList(),
    bottom,
    color,
  );
}

List<RenderFace> renderPrism(
  List<RenderPoint> top,
  List<RenderPoint> bottom,
  Color color, {
  List<List<RenderPoint>> holes = const [],
  Color? roofColor,
  bool subdivideWalls = false,
}) => [
  RenderFace(top, roofColor ?? color, holes: holes),
  for (var i = 0; i < top.length; i++)
    ...wallFaces(
      top[i],
      top[(i + 1) % top.length],
      bottom[(i + 1) % top.length],
      bottom[i],
      color,
      subdivideWalls,
    ),
];

List<RenderFace> wallFaces(
  RenderPoint a,
  RenderPoint b,
  RenderPoint c,
  RenderPoint d,
  Color color,
  bool split,
) {
  // Render-only subdivisions improve painter ordering for long walls. Bounded
  // per edge; source footprints and heights remain unchanged.
  final columns = split
      ? (math.sqrt(math.pow(b.x - a.x, 2) + math.pow(b.z - a.z, 2)) / 6)
            .ceil()
            .clamp(1, 32)
      : 1;
  final rows = split ? ((a.y - d.y).abs() / 5).ceil().clamp(1, 16) : 1;
  RenderPoint lerp(RenderPoint p, RenderPoint q, double t) => RenderPoint(
    p.x + (q.x - p.x) * t,
    p.y + (q.y - p.y) * t,
    p.z + (q.z - p.z) * t,
  );
  RenderPoint at(double x, double y) => lerp(lerp(a, b, x), lerp(d, c, x), y);
  return [
    for (var x = 0; x < columns; x++)
      for (var y = 0; y < rows; y++)
        RenderFace([
          at(x / columns, y / rows),
          at((x + 1) / columns, y / rows),
          at((x + 1) / columns, (y + 1) / rows),
          at(x / columns, (y + 1) / rows),
        ], color),
  ];
}

List<RenderFace> renderSlab(
  double ax,
  double az,
  double bx,
  double bz,
  double width,
  double top,
  double bottom,
  Color color,
) {
  final dx = bx - ax, dz = bz - az, l = math.sqrt(dx * dx + dz * dz);
  if (l == 0) return [];
  final nx = -dz / l * width / 2, nz = dx / l * width / 2;
  final t = [
    RenderPoint(ax + nx, top, az + nz),
    RenderPoint(bx + nx, top, bz + nz),
    RenderPoint(bx - nx, top, bz - nz),
    RenderPoint(ax - nx, top, az - nz),
  ];
  return renderPrism(
    t,
    t.map((p) => RenderPoint(p.x, bottom, p.z)).toList(),
    color,
  );
}

List<RenderFace> vehicleFaces(SceneVehicle vehicle) {
  final p = vehicle.anchor.worldAnchor;
  const body = Color(0xff65a9c5),
      dark = Color(0xff27323b),
      glass = Color(0xff416378);
  List<RenderFace> box(
    double x,
    double y,
    double z,
    double w,
    double h,
    double d, [
    Color color = body,
  ]) => renderBox(RenderPoint(p.x + x, p.y + y, p.z + z), w, h, d, color);
  List<RenderFace> wheel(double x, double z, double radius, double thickness) {
    final front = <RenderPoint>[], back = <RenderPoint>[];
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      front.add(
        RenderPoint(
          p.x + x + radius * math.cos(a),
          p.y + radius + radius * math.sin(a),
          p.z + z + thickness / 2,
        ),
      );
      back.add(
        RenderPoint(
          p.x + x + radius * math.cos(a),
          p.y + radius + radius * math.sin(a),
          p.z + z - thickness / 2,
        ),
      );
    }
    final hubFront = <RenderPoint>[], hubBack = <RenderPoint>[];
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      hubFront.add(
        RenderPoint(
          p.x + x + radius * .48 * math.cos(a),
          p.y + radius + radius * .48 * math.sin(a),
          p.z + z + thickness / 2 + .006,
        ),
      );
      hubBack.add(
        RenderPoint(
          p.x + x + radius * .48 * math.cos(a),
          p.y + radius + radius * .48 * math.sin(a),
          p.z + z - thickness / 2 - .006,
        ),
      );
    }
    return [
      ...renderPrism(front, back, dark),
      RenderFace(back, dark),
      RenderFace(hubFront, const Color(0xff819099)),
      RenderFace(hubBack, const Color(0xff819099)),
    ];
  }

  // Display-only diagonal frame/fork members. Their endpoints are procedural
  // silhouette proportions, never evidence measurements or solved vehicle pose.
  List<RenderFace> beam(
    double ax,
    double ay,
    double bx,
    double by,
    double thickness,
  ) {
    final dx = bx - ax, dy = by - ay, l = math.sqrt(dx * dx + dy * dy);
    if (l == 0) return [];
    final nx = -dy / l * thickness / 2, ny = dx / l * thickness / 2;
    final front = [
      RenderPoint(p.x + ax + nx, p.y + ay + ny, p.z + thickness / 2),
      RenderPoint(p.x + bx + nx, p.y + by + ny, p.z + thickness / 2),
      RenderPoint(p.x + bx - nx, p.y + by - ny, p.z + thickness / 2),
      RenderPoint(p.x + ax - nx, p.y + ay - ny, p.z + thickness / 2),
    ];
    final back = front
        .map((v) => RenderPoint(v.x, v.y, p.z - thickness / 2))
        .toList();
    return [...renderPrism(front, back, glass), RenderFace(back, glass)];
  }

  // Neutral display orientation. These are small class silhouettes, not vehicle
  // dimensions, not fitted to roads, and never persisted to the source scene.
  return switch (vehicle.anchor.className) {
    'motorcycle' => [
      ...wheel(-.8, 0, .42, .23),
      ...wheel(.8, 0, .42, .23),
      ...box(0, .55, 0, 1.25, .27, .32),
      ...box(-.2, .92, 0, .65, .18, .42, dark),
      // Tapered tank mass, generic display silhouette, not make/model evidence.
      ...renderPrism(
        [
          RenderPoint(p.x + .12, p.y + 1.06, p.z - .13),
          RenderPoint(p.x + .44, p.y + 1.01, p.z - .13),
          RenderPoint(p.x + .44, p.y + 1.01, p.z + .13),
          RenderPoint(p.x + .12, p.y + 1.06, p.z + .13),
        ],
        [
          RenderPoint(p.x + .06, p.y + .72, p.z - .21),
          RenderPoint(p.x + .56, p.y + .72, p.z - .21),
          RenderPoint(p.x + .56, p.y + .72, p.z + .21),
          RenderPoint(p.x + .06, p.y + .72, p.z + .21),
        ],
        body,
      ),
      ...beam(.8, .42, .5, 1.3, .12),
      ...beam(-.8, .42, -.15, .78, .10),
      ...box(-.1, .64, 0, .45, .35, .42, dark),
      ...box(.65, 1.35, 0, .12, .1, .65, dark),
    ],
    'bicycle' => [
      ...wheel(-.8, 0, .45, .12),
      ...wheel(.8, 0, .45, .12),
      ...beam(-.8, .45, -.12, 1.06, .08),
      ...beam(-.8, .45, 0, .5, .08),
      ...beam(0, .5, -.12, 1.06, .08),
      ...beam(-.12, 1.06, .52, 1.06, .08),
      ...beam(0, .5, .52, 1.06, .08),
      ...beam(.52, 1.06, .8, .45, .08),
      ...box(-.1, 1.2, 0, .4, .1, .25, dark),
      ...box(.7, 1.1, 0, .1, .5, .1),
      ...box(.7, 1.35, 0, .1, .1, .5, dark),
    ],
    'bus' => [
      ...box(0, 1.2, 0, 4.5, 1.75, 1.5, const Color(0xff789b91)),
      ...box(0, 1.55, 0, 4.25, .55, 1.53, glass),
      ...wheel(-1.5, .65, .4, .25),
      ...wheel(1.5, .65, .4, .25),
      ...wheel(-1.5, -.65, .4, .25),
      ...wheel(1.5, -.65, .4, .25),
    ],
    'truck' => [
      ...box(.7, 1.15, 0, 2.5, 1.5, 1.5, const Color(0xff939b9e)),
      ...box(-1.2, .95, 0, 1.25, 1.2, 1.4),
      ...box(-1.25, 1.35, 0, 1, .45, 1.43, glass),
      ...wheel(-1.25, .62, .38, .25),
      ...wheel(1.35, .62, .38, .25),
      ...wheel(-1.25, -.62, .38, .25),
      ...wheel(1.35, -.62, .38, .25),
    ],
    'car' => [
      ...box(0, .65, 0, 3, .65, 1.35),
      ...box(.1, 1.2, 0, 1.5, .55, 1.12, glass),
      ...wheel(-1, .6, .3, .2),
      ...wheel(1, .6, .3, .2),
      ...wheel(-1, -.6, .3, .2),
      ...wheel(1, -.6, .3, .2),
    ],
    _ => [],
  };
}
