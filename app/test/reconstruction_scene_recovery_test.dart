import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:iris/features/depth/application/evidence_depth_service.dart';
import 'package:iris/features/depth/domain/evidence_depth.dart';
import 'package:iris/features/depth/domain/depth_visualization.dart';
import 'package:iris/core/domain/case_local_world.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/reconstruction/application/reconstruction_scene_service.dart';
import 'package:iris/features/reconstruction/domain/reconstruction_scene.dart';
import 'package:iris/features/reconstruction/domain/evidence_reconstruction_eligibility.dart';
import 'package:iris/features/reconstruction/presentation/scene_render_data.dart';
import 'package:iris/features/reconstruction/presentation/reconstruction_painter.dart';
import 'package:iris/features/location/application/case_location_service.dart';
import 'package:iris/features/location/data/sqlite_case_location_repository.dart';
import 'package:iris/features/location/domain/case_location.dart';
import 'package:iris/features/location/domain/road_context.dart';
import 'package:iris/features/location/domain/environment_context.dart';
import 'package:iris/features/location/presentation/road_scene_viewer.dart';
import 'package:iris/features/evidence/data/evidence_storage.dart';
import 'package:iris/features/evidence/domain/evidence_image.dart';
import 'package:iris/features/geometry/application/relative_geometry_service.dart';
import 'package:iris/features/geometry/data/sqlite_geometry_repository.dart';
import 'package:iris/features/geometry/domain/relative_geometry.dart';
import 'package:iris/features/geometry/domain/evidence_world_alignment.dart';
import 'package:iris/features/geometry/application/evidence_world_alignment_service.dart';
import 'package:iris/features/geometry/data/sqlite_world_alignment_repository.dart';
import 'package:iris/features/detection/application/evidence_detection_service.dart';
import 'package:iris/features/detection/domain/evidence_detection.dart';
import 'support/case_test_harness.dart';

final date = DateTime.utc(2026);
EvidenceImage item(String caseId, String id) => EvidenceImage(
  id: id,
  caseId: caseId,
  storedRelativePath: 'test/$id',
  source: EvidenceSource.gallery,
  importedAt: date,
  fileSizeBytes: 0,
  sha256: id.padRight(64, '0'),
);
RelativeGeometry geometry(String id) => RelativeGeometry(
  evidenceId: id,
  depthSha256: 'depth',
  depthAnalyzedAt: date,
  width: 100,
  height: 100,
  points: const [
    RelativePoint(x: 1, y: 0, z: 2, u: .3, v: .7),
    RelativePoint(x: 2, y: 0, z: 4, u: .31, v: .75),
    RelativePoint(x: 3, y: 0, z: 6, u: .32, v: .8),
  ],
);
EvidenceWorldAlignment alignment(
  String caseId,
  String id,
  RoadContext roads, {
  bool stale = false,
  String? roadSnapshot,
  String? worldFrameFingerprint,
}) => EvidenceWorldAlignment(
  caseId: caseId,
  evidenceId: id,
  translationX: 10,
  translationY: 0,
  translationZ: 20,
  yaw: 0,
  uniformScale: 2,
  source: AlignmentSource.userSupplied,
  geometrySha256: stale ? 'a' * 64 : 'b' * 64,
  roadContextFingerprint: roadSnapshot ?? roadFingerprint(roads),
  worldFrameFingerprint: worldFrameFingerprint,
  provenanceVersion: worldFrameFingerprint == null
      ? null
      : EvidenceWorldAlignment.currentProvenanceVersion,
  createdAt: date,
  updatedAt: date,
);
EvidenceDetectionAnalysis detection(
  EvidenceImage e, [
  String type = 'motorcycle',
]) => EvidenceDetectionAnalysis(
  id: 'analysis-${e.id}',
  evidenceId: e.id,
  evidenceSha256: e.sha256,
  detectorSha256: EvidenceDetectionService.detectorSha256,
  thresholdPolicyVersion: EvidenceDetectionService.contractVersion,
  analyzedAt: date,
  inferenceMs: 1,
  detections: [
    EvidenceDetection(
      classId: const {
        'person': 0,
        'bicycle': 1,
        'car': 2,
        'motorcycle': 3,
        'bus': 5,
        'truck': 7,
      }[type]!,
      className: type,
      score: .8,
      ymin: .5,
      xmin: .2,
      ymax: .9,
      xmax: .4,
    ),
  ],
);
RoadContext roads(String caseId) => RoadContext(
  caseId: caseId,
  latitude: 0,
  longitude: 0,
  status: 'AVAILABLE',
  retrievedAt: date,
  roads: const [
    RoadSegment(
      id: 'test-road',
      coordinates: [
        [0, 0],
        [0, .001],
      ],
      localCoordinates: [
        [-20, 0],
        [20, 0],
      ],
    ),
  ],
);
ReconstructionScene scene({
  List<SceneEvidence> evidence = const [],
  EnvironmentContext? env,
}) => ReconstructionScene(
  caseId: 'c',
  location: CaseLocation(
    caseId: 'c',
    latitude: 0,
    longitude: 0,
    source: CaseLocationSource.mapSelection,
    updatedAt: date,
  ),
  roads: roads('c'),
  environment: env,
  evidence: evidence,
);
SceneEvidence evidence(String id, [String type = 'motorcycle']) =>
    composeSceneEvidence(
      item: item('c', id),
      capabilities: {},
      geometry: geometry(id),
      alignment: alignment('c', id, roads('c')),
      detection: detection(item('c', id), type),
    );

class GeometryFixture implements RelativeGeometryOperations {
  final seen = <String>[];
  @override
  Future<GeometryRecord?> load(EvidenceImage e) async {
    seen.add(e.id);
    return GeometryRecord(
      evidenceId: e.id,
      depthSha256: e.sha256,
      depthAnalyzedAt: date,
      algorithmVersion: 'relative-geometry-v1',
      coordinateVersion: 'iris-relative-camera-v1',
      pointCount: 3,
      path: 'test',
      sha256: 'b' * 64,
      analyzedAt: date,
    );
  }

  @override
  Future<RelativeGeometry> read(GeometryRecord r) async =>
      geometry(r.evidenceId);
  @override
  Future<GeometryRecord> generate(EvidenceImage e) =>
      throw StateError('Must not regenerate');
}

class DetectionFixture implements EvidenceDetectionOperations {
  @override
  Future<EvidenceDetectionSnapshot> load(EvidenceImage e) async =>
      EvidenceDetectionSnapshot(
        DetectionState.complete,
        analysis: detection(e),
      );
  @override
  Future<EvidenceDetectionAnalysis> analyze(EvidenceImage e) =>
      throw StateError('Must not rerun');
}

class AlignmentNavigationObserver extends NavigatorObserver {
  Completer<void>? opened;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) opened?.complete();
  }
}

class DepthFixture implements EvidenceDepthOperations {
  DepthState state = DepthState.analyzed;
  @override
  Future<EvidenceDepthSnapshot> load(EvidenceImage e) async =>
      EvidenceDepthSnapshot(
        state,
        analysis: EvidenceDepthAnalysis(
          evidenceId: e.id,
          evidenceSha256: e.sha256,
          artifactSha256: EvidenceDepthService.artifactSha256,
          analyzedAt: date,
          width: 100,
          height: 100,
          depthWidth: 518,
          depthHeight: 518,
          depthPath: 'test-only',
          min: 1,
          max: 3,
          mean: 2,
        ),
      );
  @override
  Future<EvidenceDepthAnalysis> analyze(EvidenceImage e) =>
      throw StateError('Must not rerun');
  @override
  Future<EvidenceDepthVisualization> loadVisualization(
    EvidenceDepthAnalysis a,
  ) => throw StateError('Must not regenerate');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'geometry inspection distinguishes missing, current, stale and corrupt without regeneration',
    () async {
      final h = await CaseTestHarness.create();
      addTearDown(h.dispose);
      final c = await h.repository.createCase(title: 'Fixture');
      final e = item(c.id, 'geometry-fixture');
      await h.services.evidenceRepository!.add(e);
      final repo = SqliteGeometryRepository(h.database);
      final depth = DepthFixture();
      final storage = EvidenceStorage(rootProvider: () async => h.directory);
      final service = RelativeGeometryService(
        repository: repo,
        storage: storage,
        depth: depth,
      );
      expect((await service.inspect(e)).state, GeometryInspectionState.missing);
      final bytes = Float32List.fromList([
        1,
        0,
        2,
        .3,
        .75,
      ]).buffer.asUint8List();
      const path = 'test-geometry.f32';
      final file = File(await storage.absolutePath(path));
      await file.writeAsBytes(bytes);
      await repo.save(
        GeometryRecord(
          evidenceId: e.id,
          depthSha256: e.sha256,
          depthAnalyzedAt: date,
          algorithmVersion: 'relative-geometry-v1',
          coordinateVersion: 'iris-relative-camera-v1',
          pointCount: 1,
          path: path,
          sha256: sha256.convert(bytes).toString(),
          analyzedAt: date,
        ),
      );
      expect((await service.inspect(e)).state, GeometryInspectionState.ready);
      depth.state = DepthState.stale;
      expect((await service.inspect(e)).state, GeometryInspectionState.stale);
      depth.state = DepthState.analyzed;
      await file.writeAsBytes([0]);
      expect((await service.inspect(e)).state, GeometryInspectionState.invalid);
      expect(await repo.get(e.id), isNotNull);
    },
  );
  EvidenceReconstructionEligibility evaluate({
    String type = 'motorcycle',
    ReconstructionPrerequisite detectionStatus =
        ReconstructionPrerequisite.ready,
    ReconstructionPrerequisite depthStatus = ReconstructionPrerequisite.ready,
    ReconstructionPrerequisite geometryStatus =
        ReconstructionPrerequisite.ready,
    ReconstructionPrerequisite alignmentStatus =
        ReconstructionPrerequisite.ready,
    ReconstructionPrerequisite worldStatus = ReconstructionPrerequisite.ready,
    RelativeGeometry? points,
  }) => evaluateEvidenceReconstruction(
    evidenceId: 'e',
    evidenceSha256: item('c', 'e').sha256,
    detectionState: detectionStatus,
    depthState: depthStatus,
    geometryState: geometryStatus,
    alignmentState: alignmentStatus,
    worldState: worldStatus,
    detection: detection(item('c', 'e'), type),
    geometry: points ?? geometry('e'),
    alignment: alignment('c', 'e', roads('c')),
  );
  for (final type in ['car', 'motorcycle', 'bus', 'truck', 'bicycle']) {
    test(
      '$type current prerequisites produce only evidence-derived anchor',
      () {
        final result = evaluate(type: type);
        expect(result.state, EvidenceReconstructionState.ready);
        expect(result.markers, hasLength(1));
        expect(result.markers.single.worldAnchor.x, 14);
        expect(result.markers.single.worldAnchor.z, 28);
        expect(result.classes, [type]);
      },
    );
  }
  test('non-vehicle detection cannot produce a marker', () {
    expect(
      evaluate(type: 'person').state,
      EvidenceReconstructionState.noEligibleVehicle,
    );
    expect(evaluate(type: 'person').markers, isEmpty);
  });
  for (final status in [
    ReconstructionPrerequisite.missing,
    ReconstructionPrerequisite.stale,
  ]) {
    test(
      '$status detection, depth, geometry and alignment block independently',
      () {
        final results = [
          evaluate(detectionStatus: status),
          evaluate(depthStatus: status),
          evaluate(geometryStatus: status),
          evaluate(alignmentStatus: status),
        ];
        for (final result in results) {
          expect(result.markers, isEmpty);
          expect(result.anchorAttempted, isFalse);
          expect(result.state.name.toLowerCase(), startsWith(status.name));
        }
      },
    );
  }
  test(
    'missing current roads does not weaken the saved fingerprint contract',
    () {
      expect(
        evaluate(worldStatus: ReconstructionPrerequisite.missing).state,
        EvidenceReconstructionState.missingRequiredWorldContext,
      );
    },
  );
  test('invalid alignment has no origin or road-snap fallback', () {
    final result = evaluate(
      alignmentStatus: ReconstructionPrerequisite.invalid,
    );
    expect(result.state, EvidenceReconstructionState.invalidAlignment);
    expect(result.markers, isEmpty);
  });
  test(
    'padded normalized anchor region rejects points outside real vehicle box',
    () {
      final outside = RelativeGeometry(
        evidenceId: 'e',
        depthSha256: 'depth',
        depthAnalyzedAt: date,
        width: 518,
        height: 518,
        points: const [RelativePoint(x: 8, y: 0, z: 4, u: .8, v: .8)],
      );
      final result = evaluate(points: outside);
      expect(result.state, EvidenceReconstructionState.anchorRegionHasNoPoints);
      expect(result.anchorAttempted, isTrue);
      expect(result.markers, isEmpty);
    },
  );
  test(
    'missing alignment diagnostics explain action without source identifiers',
    () {
      final result = evaluate(
        alignmentStatus: ReconstructionPrerequisite.missing,
      );
      expect(result.message, contains('Align Evidence'));
      expect(result.diagnostic(1), contains('alignment=missing'));
      expect(result.diagnostic(1), isNot(contains(item('c', 'e').sha256)));
      expect(result.diagnostic(1), isNot(contains('test/')));
    },
  );
  test(
    'vehicle framing ignores broad cloud and absent vehicle falls back to origin',
    () {
      final ready = evidence('e');
      final frame = SceneFrame.forScene(scene(evidence: [ready]));
      expect(frame.target.x, closeTo(ready.markers.single.worldAnchor.x, 10));
      expect(frame.target.z, closeTo(ready.markers.single.worldAnchor.z, 10));
      expect(frame.target.z, lessThan(ready.markers.single.worldAnchor.z));
      expect(
        ready.markers.single.worldAnchor.z,
        28,
      ); // Camera does not road-snap evidence.
      final noVehicle = composeSceneEvidence(
        item: item('c', 'e'),
        capabilities: {},
        geometry: geometry('e'),
        alignment: alignment('c', 'e', roads('c')),
      );
      final fallback = SceneFrame.forScene(scene(evidence: [noVehicle]));
      expect(fallback.target.x, 0);
      expect(fallback.target.z, 0);
      expect(fallback.span, 65);
    },
  );
  test('five display classes remain volumetric and non-analytical', () {
    for (final type in ['car', 'motorcycle', 'bus', 'truck', 'bicycle']) {
      final s = scene(evidence: [evidence('e', type)]);
      final mesh = SceneRenderData(
        s,
      ).meshes.singleWhere((m) => m.id.contains('detection'));
      expect(mesh.faces.length, greaterThan(12));
      expect(mesh.provenance.toLowerCase(), contains('representational'));
      expect(s.vehicles.single.dimensions, 'Not measured');
      expect(s.vehicles.single.orientation, 'Not established');
    }
  });
  test(
    'confirmed origin permits building retrieval without roads; no origin is unavailable',
    () {
      final s = scene();
      final noRoads = ReconstructionScene(
        caseId: 'c',
        location: s.location,
        roads: null,
        environment: null,
        evidence: [],
      );
      expect(noRoads.hasWorld, isTrue);
      expect(noRoads.hasRoadContext, isFalse);
      expect(
        SceneRenderData(noRoads).meshes.where((m) => m.id.startsWith('road/')),
        isEmpty,
      );
      expect(
        const ReconstructionScene(
          caseId: 'c',
          location: null,
          roads: null,
          environment: null,
          evidence: [],
        ).hasWorld,
        isFalse,
      );
    },
  );
  test(
    'composer includes every current evidence item, suppresses stale alignment, never regenerates',
    () async {
      final h = await CaseTestHarness.create();
      addTearDown(h.dispose);
      final c = await h.repository.createCase(title: 'Fixture');
      final repo = SqliteCaseLocationRepository(h.database);
      await repo.save(
        CaseLocation(
          caseId: c.id,
          latitude: 0,
          longitude: 0,
          source: CaseLocationSource.mapSelection,
          updatedAt: date,
        ),
      );
      await repo.saveRoadContext(roads(c.id));
      final images = [
        item(c.id, 'missing'),
        item(c.id, 'a'),
        item(c.id, 'b'),
        item(c.id, 'stale'),
      ];
      final align = EvidenceWorldAlignmentService(
        repository: SqliteWorldAlignmentRepository(h.database),
      );
      for (final e in images) {
        await h.services.evidenceRepository!.add(e);
        if (e.id == 'missing') continue;
        await align.save(
          alignment(c.id, e.id, roads(c.id), stale: e.id == 'stale'),
        );
      }
      final geo = GeometryFixture();
      final loader = ReconstructionSceneService(
        location: CaseLocationService(
          repository: repo,
          storage: EvidenceStorage(rootProvider: () async => h.directory),
          environmentProviders: [],
        ),
        loadEvidence: () async => images,
        geometry: geo,
        alignment: align,
        detection: DetectionFixture(),
      );
      final result = await loader.load(c.id);
      expect(geo.seen, ['missing', 'a', 'b', 'stale']);
      expect(result.evidence, hasLength(4));
      expect(
        result.evidence.first.eligibility!.state,
        EvidenceReconstructionState.missingAlignment,
      );
      expect(result.vehicles, hasLength(2));
      expect(result.alignedPoints, hasLength(6));
      expect(result.evidence.last.alignment, isNull);
      expect(result.evidence.last.placementStatus, contains('stale'));
      expect(result.vehicles.first.anchor.worldAnchor.x, 14);
      expect(result.vehicles.first.dimensions, 'Not measured');
      expect(result.vehicles.first.orientation, 'Not established');
    },
  );
  test(
    'same-location road refresh keeps stable alignment and resumes vehicle anchor',
    () async {
      final h = await CaseTestHarness.create();
      addTearDown(h.dispose);
      final c = await h.repository.createCase(title: 'Stable frame fixture');
      final repo = SqliteCaseLocationRepository(h.database);
      final confirmed = CaseLocation(
        caseId: c.id,
        latitude: 0,
        longitude: 0,
        source: CaseLocationSource.mapSelection,
        updatedAt: date,
      );
      await repo.save(confirmed);
      final refreshedRoads = roads(c.id);
      await repo.saveRoadContext(refreshedRoads);
      final e = item(c.id, 'stable');
      await h.services.evidenceRepository!.add(e);
      final alignments = EvidenceWorldAlignmentService(
        repository: SqliteWorldAlignmentRepository(h.database),
      );
      await alignments.save(
        alignment(
          c.id,
          e.id,
          refreshedRoads,
          roadSnapshot: 'f' * 64,
          worldFrameFingerprint: CaseLocalWorldFrame.fingerprint(
            caseId: c.id,
            originLatitude: confirmed.latitude,
            originLongitude: confirmed.longitude,
          ),
        ),
      );
      final result = await ReconstructionSceneService(
        location: CaseLocationService(
          repository: repo,
          storage: EvidenceStorage(rootProvider: () async => h.directory),
          environmentProviders: [],
        ),
        loadEvidence: () async => [e],
        geometry: GeometryFixture(),
        alignment: alignments,
        detection: DetectionFixture(),
      ).load(c.id);
      expect(result.evidence.single.alignment, isNotNull);
      expect(
        result.evidence.single.eligibility!.state,
        EvidenceReconstructionState.ready,
      );
      expect(result.vehicles, hasLength(1));
      expect(
        result.evidence.single.capabilities['Alignment road snapshot'],
        'changed',
      );
      expect(
        result.evidence.single.capabilities['Alignment world-frame provenance'],
        AlignmentProvenanceStatus.current.name,
      );
    },
  );
  test('each missing vehicle prerequisite produces no fabricated proxy', () {
    final e = item('c', 'e');
    for (final result in [
      composeSceneEvidence(item: e, capabilities: {}),
      composeSceneEvidence(
        item: e,
        capabilities: {},
        geometry: geometry(e.id),
        detection: detection(e),
      ),
      composeSceneEvidence(
        item: e,
        capabilities: {},
        geometry: geometry(e.id),
        alignment: alignment('c', e.id, roads('c')),
      ),
    ]) {
      expect(result.markers, isEmpty);
      expect(result.placementStatus, isNotEmpty);
    }
    expect(evidence('e', 'person').markers, isEmpty);
    expect(scene().vehicles, isEmpty);
  });
  test(
    'all evidence points preserve user transform and source-relative coordinates',
    () {
      final s = scene(evidence: [evidence('a'), evidence('b')]);
      expect(s.alignedPoints, hasLength(6));
      expect(s.alignedPoints.first.x, 12);
      expect(s.evidence.first.geometry!.points.first.x, 1);
      expect(s.evidence.first.alignment!.source, AlignmentSource.userSupplied);
      expect(
        SceneFrame.forScene(s).span,
        lessThan(SceneFrame.forScene(scene()).span),
      );
    },
  );
  test('source height vs display extrusion and no unmapped surroundings', () {
    for (final height in [null, '12']) {
      final f = EnvironmentFeature(
        id: 'source',
        sourceId: 'id',
        provider: 'Overture Maps',
        sourceRelease: 'test',
        elementType: 'tile_polygon',
        featureType: 'building',
        coordinates: const [
          [0, 0],
          [0, .0001],
          [.0001, .0001],
        ],
        localCoordinates: const [
          [0, 0],
          [10, 0],
          [10, 10],
        ],
        tags: {if (height != null) 'height': height},
      );
      final env = EnvironmentContext(
        caseId: 'c',
        latitude: 0,
        longitude: 0,
        status: 'AVAILABLE',
        providerState: EnvironmentProviderState.successWithFeatures,
        retrievedAt: date,
        features: [f],
      );
      final data = SceneRenderData(scene(env: env));
      final building = data.meshes.singleWhere(
        (m) => m.id.startsWith('environment/'),
      );
      expect(building.faces.first.vertices.first.y, height == null ? 6 : 12);
      expect(
        building.provenance,
        contains(height == null ? 'representational' : 'map-derived'),
      );
      expect(f.sourceHeight, height == null ? isNull : 12);
      expect(f.tags.containsKey('height'), height != null);
      expect(data.meshes.where((m) => m.label.contains('tree')), isEmpty);
      expect(data.meshes.where((m) => m.id.contains('detection')), isEmpty);
    }
    expect(
      SceneRenderData(
        scene(),
      ).meshes.where((m) => m.id.startsWith('environment/')),
      isEmpty,
    );
  });
  test(
    'roads, ground and proxies are volumetric display data with deterministic faces',
    () {
      final s = scene(evidence: [evidence('m'), evidence('c', 'car')]);
      final first = SceneRenderData(s), second = SceneRenderData(s);
      expect(first.meshes.map((m) => m.id), second.meshes.map((m) => m.id));
      expect(
        first.meshes.map((m) => m.faces.length),
        second.meshes.map((m) => m.faces.length),
      );
      expect(first.meshes.first.provenance, contains('Visualization only'));
      expect(
        first.meshes.first.faces
            .expand((f) => f.vertices)
            .map((p) => p.y)
            .toSet()
            .length,
        2,
      );
      expect(
        first.meshes.singleWhere((m) => m.id == 'road/test-road').provenance,
        contains('representational'),
      );
      final proxies = first.meshes
          .where((m) => m.id.contains('detection'))
          .toList();
      expect(proxies, hasLength(2));
      expect(proxies[0].faces.length, isNot(proxies[1].faces.length));
      expect(first.meshes.last.label, 'Incident location reference');
    },
  );
  test('camera pitch/orbit affects real XYZ projection and near clipping', () {
    const p = RenderPoint(1, 3, 2), target = RenderPoint(0, 0, 0);
    const a = SceneCamera(
      target: target,
      yaw: 0,
      pitch: 0,
      distance: 10,
      viewport: Size(400, 400),
    );
    const b = SceneCamera(
      target: target,
      yaw: 1,
      pitch: -.6,
      distance: 10,
      viewport: Size(400, 400),
    );
    expect(a.project(p), isNot(b.project(p)));
    expect(
      a
          .clipNear(const [
            RenderPoint(0, 0, -11),
            RenderPoint(2, 0, 0),
            RenderPoint(0, 2, 0),
          ])
          .every((v) => v.z >= .099999),
      isTrue,
    );
  });
  test(
    'depth ordering deterministic, environment refresh repaints and pinch does not compound',
    () {
      final data = SceneRenderData(scene(evidence: [evidence('a')]));
      final camera = SceneCamera(
        target: data.frame.target,
        yaw: .5,
        pitch: -.62,
        distance: 60,
        viewport: const Size(400, 400),
      );
      final faces = projectFaces(data, camera, true),
          again = projectFaces(data, camera, true);
      expect(faces.map((f) => f.order), again.map((f) => f.order));
      for (var i = 1; i < faces.length; i++) {
        expect(faces[i - 1].depth, greaterThanOrEqualTo(faces[i].depth));
      }
      ReconstructionPainter painter(SceneRenderData d) => ReconstructionPainter(
        data: d,
        yaw: .5,
        pitch: -.62,
        zoom: 1,
        pan: Offset.zero,
        evidence: false,
        centerlines: false,
        grid: false,
        environment: true,
      );
      expect(
        painter(SceneRenderData(data.source)).shouldRepaint(painter(data)),
        isTrue,
      );
      expect(painter(data).shouldRepaint(painter(data)), isFalse);
      expect(sceneGestureZoom(1, 1.2), 1.2);
      expect(sceneGestureZoom(1, 1.5), 1.5);
      expect(sceneGestureZoom(2, 1.5), 3);
    },
  );
  testWidgets(
    'Sources alignment editor cancel preserves absence and explicit save recomposes without inference',
    (tester) async {
      final h = (await tester.runAsync(CaseTestHarness.create))!;
      addTearDown(() => tester.runAsync(h.dispose));
      late ReconstructionSceneService loader;
      late EvidenceWorldAlignmentService align;
      late ReconstructionScene initial;
      late String evidenceId;
      await tester.runAsync(() async {
        final c = await h.repository.createCase(title: 'Fixture');
        final e = item(c.id, 'alignment-fixture');
        evidenceId = e.id;
        await h.services.evidenceRepository!.add(e);
        final repo = SqliteCaseLocationRepository(h.database);
        await repo.save(
          CaseLocation(
            caseId: c.id,
            latitude: 0,
            longitude: 0,
            source: CaseLocationSource.mapSelection,
            updatedAt: date,
          ),
        );
        await repo.saveRoadContext(roads(c.id));
        align = EvidenceWorldAlignmentService(
          repository: SqliteWorldAlignmentRepository(h.database),
        );
        loader = ReconstructionSceneService(
          location: CaseLocationService(
            repository: repo,
            storage: EvidenceStorage(rootProvider: () async => h.directory),
            environmentProviders: [],
          ),
          loadEvidence: () async => [e],
          geometry: GeometryFixture(),
          alignment: align,
          detection: DetectionFixture(),
        );
        initial = await loader.load(c.id);
      });
      final observer = AlignmentNavigationObserver();
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          home: RoadSceneViewer(
            scene: initial,
            loader: loader,
            service: loader.location,
          ),
        ),
      );
      await tester.tap(find.text('Sources & evidence'));
      await tester.pumpAndSettle();
      Future<void>? editorCompletion;
      Future<void> openEditor() async {
        await tester.ensureVisible(find.text('Align Evidence 1'));
        observer.opened = Completer<void>();
        await tester.runAsync(() async {
          final button = tester.widget<OutlinedButton>(
            find.ancestor(
              of: find.text('Align Evidence 1'),
              matching: find.byWidgetPredicate((w) => w is OutlinedButton),
            ),
          );
          editorCompletion = (button.onPressed as dynamic)() as Future<void>;
        });
        // Navigation observer delivery is post-frame. Pump frames while SQLite
        // completes on the real event loop, rather than blocking frame delivery.
        final watch = Stopwatch()..start();
        while (!observer.opened!.isCompleted &&
            watch.elapsed < const Duration(seconds: 10)) {
          await tester.runAsync(() => Future<void>(() {}));
          await tester.pump();
        }
        expect(observer.opened!.isCompleted, isTrue);
        await tester.pumpAndSettle();
      }

      await openEditor();
      expect(find.text('Save Alignment'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Cancel'));
        await editorCompletion!.timeout(const Duration(seconds: 10));
      });
      await tester.pumpAndSettle();
      expect(await tester.runAsync(() => align.load(evidenceId)), isNull);
      await openEditor();
      await tester.runAsync(() async {
        await tester.tap(find.text('Save Alignment'));
        await editorCompletion!.timeout(const Duration(seconds: 10));
      });
      await tester.pumpAndSettle();
      final saved = await tester.runAsync(() => align.load(evidenceId));
      expect(saved!.source, AlignmentSource.userSupplied);
      final painter =
          tester
                  .widget<CustomPaint>(find.byKey(const Key('unified-scene')))
                  .painter!
              as ReconstructionPainter;
      expect(painter.data.source.vehicles, hasLength(1));
      expect(
        painter.data.source.evidence.single.eligibility!.state,
        EvidenceReconstructionState.ready,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'unified viewer clean defaults, independent analysis overlays and reset',
    (tester) async {
      final h = (await tester.runAsync(CaseTestHarness.create))!;
      addTearDown(() => tester.runAsync(h.dispose));
      final service = CaseLocationService(
        repository: SqliteCaseLocationRepository(h.database),
        storage: EvidenceStorage(rootProvider: () async => h.directory),
        environmentProviders: [],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: RoadSceneViewer(
            scene: scene(evidence: [evidence('a')]),
            loader: ReconstructionSceneService(
              location: service,
              loadEvidence: () async => [],
            ),
            service: service,
          ),
        ),
      );
      ReconstructionPainter current() =>
          tester
                  .widget<CustomPaint>(find.byKey(const Key('unified-scene')))
                  .painter!
              as ReconstructionPainter;
      expect(current().evidence, isFalse);
      expect(current().grid, isFalse);
      expect(current().centerlines, isFalse);
      final sources = tester.widget<ExpansionTile>(
        find.byKey(const Key('sources-evidence')),
      );
      expect(sources.initiallyExpanded, isFalse);
      await tester.tap(find.text('Analysis View'));
      await tester.pump();
      expect(current().evidence, isTrue);
      await tester.tap(find.text('World grid'));
      await tester.pump();
      expect(current().grid, isTrue);
      expect(current().centerlines, isFalse);
      await tester.drag(
        find.byKey(const Key('unified-scene')),
        const Offset(30, 20),
      );
      // Complete the SDK double-tap recognizer's minimum tracking interval.
      await tester.pump(kDoubleTapMinTime);
      expect(current().yaw, isNot(.5));
      await tester.tap(find.byTooltip('Reset camera'));
      await tester.pump();
      expect(current().yaw, current().data.frame.yaw);
      expect(current().pitch, current().data.frame.pitch);
      final beforeFullscreen = current();
      await tester.tap(find.byTooltip('Fullscreen'));
      await tester.pumpAndSettle();
      expect(find.text('Sources & evidence'), findsNothing);
      expect(current().yaw, beforeFullscreen.yaw);
      expect(current().pitch, beforeFullscreen.pitch);
      expect(current().grid, beforeFullscreen.grid);
      await tester.tap(find.byTooltip('Exit fullscreen'));
      await tester.pumpAndSettle();
      expect(find.text('Sources & evidence'), findsOneWidget);
      expect(current().zoom, beforeFullscreen.zoom);
      await tester.tap(find.text('Scene View'));
      await tester.pump();
      expect(current().grid, isFalse);
      expect(current().evidence, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
