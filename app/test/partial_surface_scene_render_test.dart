import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/geometry/domain/evidence_vehicle_marker.dart';
import 'package:iris/features/geometry/domain/evidence_world_alignment.dart';
import 'package:iris/features/geometry/domain/relative_geometry.dart';
import 'package:iris/features/partial_surface/domain/evidence_partial_surface.dart';
import 'package:iris/features/reconstruction/domain/reconstruction_scene.dart';
import 'package:iris/features/reconstruction/presentation/reconstruction_painter.dart';
import 'package:iris/features/reconstruction/presentation/scene_render_data.dart';

void main() {
  final alignment = EvidenceWorldAlignment(
    caseId: 'case',
    evidenceId: 'evidence',
    translationX: 0,
    translationY: 0,
    translationZ: 0,
    yaw: 0,
    uniformScale: 1,
    source: AlignmentSource.userSupplied,
    geometrySha256: 'a' * 64,
    roadContextFingerprint: 'b' * 64,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
  const vertex = PartialSurfaceVertex(
    x: 0,
    y: 0,
    z: 1,
    u: .5,
    v: .5,
    argb: 0xffe46f26,
  );
  final part = EvidencePartialSurfacePart(
    id: 'part',
    segmentationMaskId: 'mask',
    detectionIndex: 0,
    classId: 3,
    className: 'motorcycle',
    maskSha256: 'c' * 64,
    meshFileRelativePath: 'surface.ips',
    meshSha256: 'd' * 64,
    vertexCount: 3,
    triangleCount: 1,
  );
  final mesh = EvidencePartialSurfaceMesh(
    part: part,
    vertices: const <PartialSurfaceVertex>[
      vertex,
      PartialSurfaceVertex(x: 1, y: 0, z: 1, u: .9, v: .5, argb: 0xffe46f26),
      PartialSurfaceVertex(x: 0, y: 1, z: 1, u: .5, v: .9, argb: 0xffe46f26),
    ],
    triangles: const <PartialSurfaceTriangle>[PartialSurfaceTriangle(0, 1, 2)],
  );
  final marker = EvidenceVehicleMarker(
    detectionIndex: 0,
    className: 'motorcycle',
    score: .9,
    ymin: .2,
    xmin: .2,
    ymax: .8,
    xmax: .8,
    evidenceAnchor: const RelativePoint(x: 0, y: 0, z: 1, u: .5, v: .5),
    worldAnchor: const RelativePoint(x: 0, y: 0, z: 1, u: .5, v: .5),
  );

  ReconstructionScene scene({bool withSurface = true}) => ReconstructionScene(
    caseId: 'case',
    location: null,
    roads: null,
    environment: null,
    evidence: <SceneEvidence>[
      SceneEvidence(
        evidenceId: 'evidence',
        label: 'Evidence',
        capabilities: const <String, String>{},
        placementStatus: 'Ready',
        alignment: alignment,
        markers: <EvidenceVehicleMarker>[marker],
        partialSurfaces: withSurface
            ? <EvidencePartialSurfaceMesh>[mesh]
            : const <EvidencePartialSurfaceMesh>[],
      ),
    ],
  );

  test(
    'current visible mesh replaces its generic class proxy, preserving source colour',
    () {
      final data = SceneRenderData(scene());
      final surface = data.meshes.singleWhere(
        (item) => item.id == 'evidence-surface/evidence/detection/0',
      );

      expect(surface.faces, hasLength(1));
      expect(surface.faces.single.color, const Color(0xffe46f26));
      expect(surface.faces.single.preserveSourceColour, isTrue);
      expect(
        shadeDisplayFace(surface.faces.single),
        isNot(const Color(0xffe46f26)),
      );
      expect(
        data.meshes.where((item) => item.id == 'evidence/detection/0'),
        isEmpty,
      );
    },
  );

  test(
    'without a current visible mesh, the existing display proxy remains available',
    () {
      final data = SceneRenderData(scene(withSurface: false));
      expect(
        data.meshes.where((item) => item.id == 'evidence/detection/0'),
        hasLength(1),
      );
    },
  );
}
