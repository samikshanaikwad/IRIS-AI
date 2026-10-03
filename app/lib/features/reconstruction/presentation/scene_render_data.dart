import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../domain/reconstruction_scene.dart';

/// DISPLAY ONLY. These mesh dimensions must never be passed to analytical or
/// future physics code. Source facts live in ReconstructionScene, separately.
class RenderPoint {
  const RenderPoint(this.x, this.y, this.z);
  final double x, y, z;
}

class RenderFace {
  const RenderFace(this.vertices, this.color, {this.holes = const []});
  final List<RenderPoint> vertices;
  final List<List<RenderPoint>> holes;
  final Color color;
}

class RenderMesh {
  const RenderMesh(this.id, this.label, this.provenance, this.faces);
  final String id, label, provenance;
  final List<RenderFace> faces;
}

class SceneFrame {
  const SceneFrame(this.target, this.span);
  final RenderPoint target;
  final double span;
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
    if (anchors.isEmpty) return const SceneFrame(RenderPoint(0, 0, 0), 65);
    final xs = anchors.map((p) => p.x),
        zs = anchors.map((p) => p.z),
        ys = anchors.map((p) => p.y);
    final minX = xs.reduce(math.min),
        maxX = xs.reduce(math.max),
        minZ = zs.reduce(math.min),
        maxZ = zs.reduce(math.max);
    return SceneFrame(
      RenderPoint(
        (minX + maxX) / 2,
        (ys.reduce(math.min) + ys.reduce(math.max)) / 2,
        (minZ + maxZ) / 2,
      ),
      (math.max(maxX - minX, maxZ - minZ) * 1.8 + 24).clamp(32, 160),
    );
  }
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

  Offset screen(RenderPoint cameraPoint) => Offset(
    viewport.width / 2 +
        cameraPoint.x * viewport.shortestSide * .95 / cameraPoint.z,
    viewport.height / 2 -
        cameraPoint.y * viewport.shortestSide * .95 / cameraPoint.z,
  );
  Offset? project(RenderPoint p) {
    final v = view(p);
    return v.z < .1 ? null : screen(v);
  }

  List<RenderPoint> clipNear(List<RenderPoint> world) {
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
}

class SceneRenderData {
  SceneRenderData(this.source) : frame = SceneFrame.forScene(source) {
    meshes = _build();
  }
  final ReconstructionScene source;
  final SceneFrame frame;
  late final List<RenderMesh> meshes;
  List<RenderMesh> _build() {
    final out = <RenderMesh>[];
    final groundFaces = <RenderFace>[];
    // Small tiles improve painter depth ordering; this is a neutral reference
    // platform, not evidence of ground elevation/surface or a mapped land area.
    final extent = math.max(frame.span * .7, 32.0), step = extent / 5;
    for (var i = -5; i < 5; i++) {
      for (var j = -5; j < 5; j++) {
        groundFaces.addAll(
          renderBox(
            RenderPoint(
              frame.target.x + (i + .5) * step,
              -.3,
              frame.target.z + (j + .5) * step,
            ),
            step,
            .5,
            step,
            const Color(0xff34424a),
          ),
        );
      }
    }
    out.add(
      RenderMesh(
        'reference-ground',
        'Reference ground',
        'Visualization only • Terrain elevation not established',
        groundFaces,
      ),
    );
    for (final road in source.roads?.roads ?? []) {
      final width =
          road.width != null && road.width!.isFinite && road.width! > 0
          ? road.width!
          : null;
      final faces = <RenderFace>[];
      for (var i = 1; i < road.localCoordinates.length; i++) {
        final a = road.localCoordinates[i - 1], b = road.localCoordinates[i];
        final length = math.sqrt(
          math.pow(b[0] - a[0], 2) + math.pow(b[1] - a[1], 2),
        );
        final pieces = math.max(1, (length / 8).ceil());
        for (var k = 0; k < pieces; k++) {
          faces.addAll(
            renderSlab(
              a[0] + (b[0] - a[0]) * k / pieces,
              a[1] + (b[1] - a[1]) * k / pieces,
              a[0] + (b[0] - a[0]) * (k + 1) / pieces,
              a[1] + (b[1] - a[1]) * (k + 1) / pieces,
              width ?? 5.0,
              .12,
              -.08,
              const Color(0xff65717a),
            ),
          );
        }
      }
      out.add(
        RenderMesh(
          'road/${road.id}',
          road.name ?? 'Mapped road',
          'Centerline: OpenStreetMap • ${width == null ? 'Surface width: representational / unknown' : 'Width: explicit map attribute'} • Thickness: display only',
          faces,
        ),
      );
    }
    for (final feature in source.environmentFeatures) {
      final faces = <RenderFace>[];
      var appearance = 'Display dimensions representational';
      if (feature.featureType == 'building' &&
          feature.localCoordinates.length >= 3) {
        final height = feature.sourceHeight ?? 6.0;
        final top = feature.localCoordinates
            .map((p) => RenderPoint(p[0], height, p[1]))
            .toList();
        final bottom = feature.localCoordinates
            .map((p) => RenderPoint(p[0], 0, p[1]))
            .toList();
        faces.addAll(
          renderPrism(
            top,
            bottom,
            const Color(0xffa4afb6),
            holes: feature.localHoles
                .map(
                  (r) => r.map((p) => RenderPoint(p[0], height, p[1])).toList(),
                )
                .toList(),
          ),
        );
        for (final ring in feature.localHoles) {
          final innerTop = ring
              .map((p) => RenderPoint(p[0], height, p[1]))
              .toList();
          final innerBottom = ring
              .map((p) => RenderPoint(p[0], 0, p[1]))
              .toList();
          faces.addAll(
            renderPrism(innerTop, innerBottom, const Color(0xff77838d)).skip(1),
          );
        }
        appearance = feature.sourceHeight == null
            ? 'Height: representational — source height unavailable'
            : 'Height: map-derived source attribute';
      } else if (feature.featureType == 'tree' &&
          feature.localCoordinates.isNotEmpty) {
        final p = feature.localCoordinates.first;
        faces.addAll(
          renderBox(
            RenderPoint(p[0], 1.4, p[1]),
            .35,
            2.8,
            .35,
            const Color(0xff75634e),
          ),
        );
        faces.addAll(
          renderBox(
            RenderPoint(p[0], 3.2, p[1]),
            2.0,
            2.2,
            2.0,
            const Color(0xff527362),
          ),
        );
      } else if (feature.featureType == 'barrier') {
        for (var i = 1; i < feature.localCoordinates.length; i++) {
          final a = feature.localCoordinates[i - 1],
              b = feature.localCoordinates[i];
          faces.addAll(
            renderSlab(
              a[0],
              a[1],
              b[0],
              b[1],
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
    for (final vehicle in source.vehicles) {
      out.add(
        RenderMesh(
          vehicle.id,
          vehicle.anchor.className,
          'Evidence: ${vehicle.evidenceId}\nDetection score: ${vehicle.anchor.score.toStringAsFixed(3)}\n'
          'Anchor: relative image geometry + user alignment\nRepresentational display proportions\nDimensions: not measured • Orientation: not established\n'
          'Bounding-box/background uncertainty; segmentation unavailable',
          vehicleFaces(vehicle),
        ),
      );
    }
    out.add(
      RenderMesh(
        'incident-reference',
        ReconstructionScene.originLabel,
        'Confirmed incident map location • No collision point established',
        renderBox(
          const RenderPoint(0, .7, 0),
          .5,
          1.4,
          .5,
          const Color(0xffcd7c64),
        ),
      ),
    );
    return List.unmodifiable(out);
  }
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
}) => [
  RenderFace(top, color, holes: holes),
  for (var i = 0; i < top.length; i++)
    RenderFace([
      top[i],
      top[(i + 1) % top.length],
      bottom[(i + 1) % top.length],
      bottom[i],
    ], Color.lerp(color, Colors.black, i.isEven ? .28 : .42)!),
];
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
    return [...renderPrism(front, back, dark), RenderFace(back, dark)];
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
      ...box(.32, .85, 0, .48, .35, .38),
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
