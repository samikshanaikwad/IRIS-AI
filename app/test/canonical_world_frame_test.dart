import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/domain/case_local_world.dart';
import 'package:iris/features/detection/domain/evidence_detection.dart';
import 'package:iris/features/geometry/domain/evidence_vehicle_marker.dart';
import 'package:iris/features/geometry/domain/evidence_world_alignment.dart';
import 'package:iris/features/geometry/domain/relative_geometry.dart';
import 'package:iris/features/geometry/presentation/evidence_alignment_section.dart';
import 'package:iris/features/location/domain/case_location.dart';
import 'package:iris/features/location/domain/environment_context.dart';
import 'package:iris/features/location/domain/environment_parser.dart';
import 'package:iris/features/location/domain/road_context.dart';
import 'package:iris/features/reconstruction/application/reconstruction_scene_service.dart';
import 'package:iris/features/reconstruction/domain/reconstruction_scene.dart';
import 'package:iris/features/reconstruction/presentation/scene_render_data.dart';

final _date = DateTime.utc(2026);

RoadContext _roads() => RoadContext(
  caseId: 'case',
  latitude: 10,
  longitude: 20,
  status: 'AVAILABLE',
  retrievedAt: _date,
  roads: const [
    RoadSegment(
      id: 'road',
      coordinates: [
        [10, 20],
        [10, 20.001],
      ],
      localCoordinates: [
        [-20, 8],
        [20, 8],
      ],
    ),
  ],
);

EvidenceWorldAlignment _alignment() => EvidenceWorldAlignment(
  caseId: 'case',
  evidenceId: 'evidence',
  translationX: 3,
  translationY: 0,
  translationZ: 4,
  yaw: math.pi / 2,
  uniformScale: 2,
  source: AlignmentSource.userSupplied,
  geometrySha256: 'a' * 64,
  roadContextFingerprint: roadFingerprint(_roads()),
  createdAt: _date,
  updatedAt: _date,
);

const _point = RelativePoint(x: 2, y: 1, z: 1, u: .5, v: .75);

RelativeGeometry _geometry() => RelativeGeometry(
  evidenceId: 'evidence',
  depthSha256: 'b' * 64,
  depthAnalyzedAt: _date,
  width: 100,
  height: 200,
  points: const [_point],
);

void main() {
  test('TASK011 geographic conversion has one canonical origin and axes', () {
    expect(
      CaseLocalWorldFrame.geographicToMapXZ(
        latitude: 10,
        longitude: 20,
        originLatitude: 10,
        originLongitude: 20,
      ),
      [0, 0],
    );
    final north = localMetricPoint(10.001, 20, 10, 20);
    final east = localMetricPoint(10, 20.001, 10, 20);
    expect(north[0], closeTo(0, 1e-9));
    expect(north[1], greaterThan(0));
    expect(east[0], greaterThan(0));
    expect(east[1], closeTo(0, 1e-9));
    expect(CaseLocalWorldFrame.contract, contains('X=east'));
    expect(ReconstructionScene.coordinateSystem, contains('X east'));
  });

  test('road and building conversion use identical X/Z convention', () {
    final road = localMetricPoint(10.001, 20.002, 10, 20);
    final parsed = parseEnvironmentElements(
      elements: [
        {
          'type': 'way',
          'id': 1,
          'tags': {'building': 'yes'},
          'geometry': [
            {'lat': 10.001, 'lon': 20.002},
            {'lat': 10.001, 'lon': 20.003},
            {'lat': 10.002, 'lon': 20.003},
            {'lat': 10.001, 'lon': 20.002},
          ],
        },
      ],
      originLatitude: 10,
      originLongitude: 20,
    );
    expect(
      parsed.features.single.localCoordinates.first[0],
      closeTo(road[0], 1e-9),
    );
    expect(
      parsed.features.single.localCoordinates.first[1],
      closeTo(road[1], 1e-9),
    );
  });

  test('persisted transform is scale then positive yaw then translation', () {
    final value = _alignment().transform(_point);
    // (4, 2) rotated +90 around Y becomes (-2, 4), then translated.
    expect(value.x, closeTo(1, 1e-9));
    expect(value.y, closeTo(2, 1e-9));
    expect(value.z, closeTo(8, 1e-9));
  });

  test(
    'alignment preview and reconstruction share evidence-road relationship',
    () {
      final alignment = _alignment(), geometry = _geometry(), roads = _roads();
      final marker = deriveVehicleMarkers(
        analysis: EvidenceDetectionAnalysis(
          id: 'analysis',
          evidenceId: 'evidence',
          evidenceSha256: 'c' * 64,
          detectorSha256: 'd' * 64,
          thresholdPolicyVersion: 'test',
          analyzedAt: _date,
          inferenceMs: 1,
          detections: const [
            EvidenceDetection(
              classId: 3,
              className: 'motorcycle',
              score: .9,
              ymin: .5,
              xmin: .4,
              ymax: .9,
              xmax: .6,
            ),
          ],
        ),
        geometry: geometry,
        alignment: alignment,
      ).single;
      final evidence = SceneEvidence(
        evidenceId: 'evidence',
        label: 'Evidence',
        capabilities: const {},
        placementStatus: 'ready',
        geometry: geometry,
        alignment: alignment,
        markers: [marker],
      );
      final scene = ReconstructionScene(
        caseId: 'case',
        location: CaseLocation(
          caseId: 'case',
          latitude: 10,
          longitude: 20,
          source: CaseLocationSource.mapSelection,
          updatedAt: _date,
        ),
        roads: roads,
        environment: null,
        evidence: [evidence],
      );
      expect(alignmentPreviewRoadBucket(roads, geometry, alignment), 'within5');
      final diagnostics = SceneRenderData(scene).roadDiagnostics;
      expect(diagnostics.nearestEvidenceBucket, 'within5');
      expect(diagnostics.nearestAlignedGeometryBucket, 'within5');
      expect(diagnostics.safeSummary, contains('canonicalFrame=ready'));
      expect(diagnostics.safeSummary, isNot(contains('10.')));
      expect(diagnostics.safeSummary, isNot(contains('test/')));
      expect(scene.vehicles.single.anchor.worldAnchor.x, closeTo(1, 1e-9));
      expect(scene.vehicles.single.anchor.worldAnchor.z, closeTo(8, 1e-9));
    },
  );

  test('canonical composition never snaps aligned evidence to a road', () {
    final alignment = EvidenceWorldAlignment(
      caseId: 'case',
      evidenceId: 'evidence',
      translationX: 80,
      translationY: 0,
      translationZ: 90,
      yaw: 0,
      uniformScale: 1,
      source: AlignmentSource.userSupplied,
      geometrySha256: 'a' * 64,
      roadContextFingerprint: roadFingerprint(_roads()),
      createdAt: _date,
      updatedAt: _date,
    );
    final transformed = alignment.transform(_point);
    expect(transformed.x, 82);
    expect(transformed.z, 91);
    expect(
      mapDistanceBucket(
        nearestMapPolylineDistance(
          CaseLocalWorldPoint(
            xEast: transformed.x,
            yUp: transformed.y,
            zNorth: transformed.z,
          ),
          _roads().roads.map((r) => r.localCoordinates),
        ),
      ),
      'over40',
    );
  });

  test('display conversion does not mutate map or relative source data', () {
    final building = EnvironmentFeature(
      id: 'building',
      elementType: 'way',
      featureType: 'building',
      coordinates: const [
        [10, 20],
        [10, 20.001],
        [10.001, 20.001],
      ],
      localCoordinates: const [
        [0, 0],
        [10, 0],
        [10, 10],
      ],
      tags: const {},
    );
    final original = building.localCoordinates.map(List<double>.of).toList();
    expect(CaseLocalWorldPoint.fromMapXZ(original.first).mapXZ, [0, 0]);
    expect(building.localCoordinates, original);
    expect(_geometry().points.single, same(_point));
  });
}
