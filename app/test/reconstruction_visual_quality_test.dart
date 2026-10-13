import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/location/domain/building_appearance.dart';
import 'package:iris/features/location/domain/environment_context.dart';
import 'package:iris/features/location/domain/road_context.dart';
import 'package:iris/features/location/presentation/road_scene_viewer.dart';
import 'package:iris/features/reconstruction/domain/reconstruction_scene.dart';
import 'package:iris/features/reconstruction/presentation/reconstruction_painter.dart';
import 'package:iris/features/reconstruction/presentation/scene_render_data.dart';
import 'reconstruction_scene_recovery_test.dart' as fixtures;

EnvironmentFeature building({
  Map<String, String> tags = const {},
  List<List<double>>? ring,
}) => EnvironmentFeature(
  id: 'test-building',
  elementType: 'way',
  featureType: 'building',
  coordinates: const [
    [0, 0],
    [0, .0001],
    [.0001, .0001],
  ],
  localCoordinates:
      ring ??
      const [
        [-12, -8],
        [-3, -8],
        [-3, 5],
        [-12, 5],
        [-12, -8],
      ],
  tags: tags,
);
EnvironmentContext environment(List<EnvironmentFeature> buildings) =>
    EnvironmentContext(
      caseId: 'c',
      latitude: 0,
      longitude: 0,
      status: 'AVAILABLE',
      providerState: EnvironmentProviderState.successWithFeatures,
      retrievedAt: fixtures.date,
      features: buildings,
    );

void main() {
  test(
    'appearance counts distinguish genuine source attributes and unknown surfaces',
    () {
      final result = buildingAppearanceCounts([
        building(
          tags: {
            'building:colour': 'red',
            'roof:colour': '#fff',
            'height': '8',
          },
        ),
        building(
          tags: {'building:colour': '#bad-color', 'building:material': 'brick'},
        ),
      ]);
      expect(result, {
        'buildings': 2,
        'wallColor': 1,
        'roofColor': 1,
        'material': 1,
        'height': 1,
        'unknownNeutral': 1,
      });
      expect(buildingAppearanceCounts([]).values.every((v) => v == 0), isTrue);
    },
  );
  test(
    'reference ground cannot checkerboard-occlude road or building bases',
    () {
      final data = SceneRenderData(
        fixtures.scene(env: environment([building()])),
      );
      final camera = SceneCamera(
        target: data.frame.target,
        yaw: .5,
        pitch: -.78,
        distance: 60,
        viewport: const Size(500, 500),
      );
      final faces = scenePaintOrder(projectFaces(data, camera, true));
      final lastGround = faces.lastIndexWhere(
        (f) => f.mesh.id == 'reference-ground',
      );
      final firstRoad = faces.indexWhere((f) => f.mesh.id.startsWith('road/'));
      final lastRoad = faces.lastIndexWhere(
        (f) => f.mesh.id.startsWith('road/'),
      );
      final firstBuilding = faces.indexWhere(
        (f) => f.mesh.id.startsWith('environment/'),
      );
      expect(firstRoad, greaterThan(lastGround));
      expect(firstBuilding, greaterThan(lastRoad));
      final solids = faces
          .where((f) => f.mesh.id.startsWith('environment/'))
          .toList();
      for (var i = 1; i < solids.length; i++) {
        expect(solids[i - 1].depth, greaterThanOrEqualTo(solids[i].depth));
      }
    },
  );
  for (final sample in {
    '#D8C5A3': 0xffd8c5a3,
    '#abc': 0xffaabbcc,
    'white': 0xffffffff,
    ' navy ': 0xff000080,
  }.entries) {
    test('source color ${sample.key} parsed without palette inference', () {
      expect(parseMapColor(sample.key), sample.value);
    });
  }
  for (final source in [
    'brick',
    '#zzzzzz',
    '#12345678',
    'red;blue',
    'rgb(random)',
    '',
  ]) {
    test('invalid or ambiguous color "$source" remains unknown', () {
      final a = SurfaceAppearance.fromSource(source, 'OpenStreetMap');
      expect(a.argb, isNull);
      expect(a.provenance, AppearanceProvenance.unknownNeutral);
    });
  }
  test('wall and roof separate source colors survive persistence', () {
    final f = building(
      tags: {
        'building:colour': '#D8C5A3',
        'roof:colour': 'blue',
        'building:material': 'brick',
      },
    );
    final json = f.toJson(), loaded = EnvironmentFeature.fromJson(json);
    expect(loaded.wallAppearance.argb, 0xffd8c5a3);
    expect(loaded.roofAppearance.argb, 0xff0000ff);
    expect(loaded.wallAppearance.provenance, AppearanceProvenance.mapDerived);
    expect(json['appearance'], isNotNull);
    expect(loaded.tags, f.tags);
    expect(loaded.wallAppearance.provider, 'OpenStreetMap');
  });
  test('material alone cannot establish a color or observed appearance', () {
    final f = building(tags: {'building:material': 'brick'});
    expect(f.wallAppearance.argb, isNull);
    expect(f.wallAppearance.label, contains('neutral'));
    expect(
      f.wallAppearance.provenance,
      isNot(AppearanceProvenance.evidenceObserved),
    );
  });
  test(
    'building roof and wall use genuine base colors and display shading is separate',
    () {
      final f = building(
        tags: {
          'building:colour': '#D8C5A3',
          'roof:colour': '#808080',
          'height': '9',
        },
      );
      final data = SceneRenderData(fixtures.scene(env: environment([f])));
      final mesh = data.meshes.singleWhere(
        (m) => m.id.startsWith('environment/'),
      );
      expect(mesh.faces.first.color, const Color(0xff808080));
      expect(mesh.faces[1].color, const Color(0xffd8c5a3));
      shadeDisplayFace(mesh.faces[1]);
      expect(mesh.faces[1].color, const Color(0xffd8c5a3));
      expect(mesh.provenance, contains('Height: map-derived'));
      expect(mesh.faces.first.vertices.every((p) => p.y == 9), isTrue);
    },
  );
  test(
    'unknown heights and appearance deterministic, not evidence-observed',
    () {
      final f = building(),
          data = SceneRenderData(fixtures.scene(env: environment([f])));
      final a = data.meshes.singleWhere((m) => m.id.startsWith('environment/'));
      final b = SceneRenderData(
        data.source,
      ).meshes.singleWhere((m) => m.id.startsWith('environment/'));
      expect(a.faces.first.vertices.first.y, 6);
      expect(a.faces.first.color, b.faces.first.color);
      expect(a.provenance, contains('Height: representational'));
      expect(a.provenance, contains('Not established — neutral visualization'));
      expect(f.tags, isEmpty);
    },
  );
  test('initial camera avoids a building occupying original camera volume', () {
    final base = fixtures.scene(evidence: [fixtures.evidence('e')]);
    final old = SceneFrame.forScene(base), eye = old.eye;
    final f = building(
      tags: {'height': '80'},
      ring: [
        [eye.x - 8, eye.z - 8],
        [eye.x + 8, eye.z - 8],
        [eye.x + 8, eye.z + 8],
        [eye.x - 8, eye.z + 8],
      ],
    );
    final frame = SceneFrame.forScene(
      fixtures.scene(evidence: base.evidence, env: environment([f])),
    );
    expect(
      insideFootprint(frame.eye.x, frame.eye.z, f.localCoordinates),
      isFalse,
    );
    expect(
      nearFootprint(frame.eye.x, frame.eye.z, f.localCoordinates, 3),
      isFalse,
    );
    expect(frame.target.x, old.target.x);
    expect(frame.target.z, old.target.z);
    expect(frame.yaw, isNot(old.yaw));
  });
  test(
    'incident framing keeps evidence central without provider-radius zoom',
    () {
      final base = fixtures.scene(
        evidence: [fixtures.evidence('e')],
        env: environment([
          building(
            ring: const [
              [90, 90],
              [140, 90],
              [140, 140],
              [90, 140],
            ],
          ),
        ]),
      );
      // Test-only composition approximates the accepted physical failure:
      // a real-source road beside the incident, a vehicle, and obstructive
      // context buildings. It is never reachable from production case data.
      final s = ReconstructionScene(
        caseId: base.caseId,
        location: base.location,
        roads: RoadContext(
          caseId: base.caseId,
          latitude: 0,
          longitude: 0,
          status: 'AVAILABLE',
          retrievedAt: fixtures.date,
          roads: const [
            RoadSegment(
              id: 'qa-real-source-road',
              coordinates: [
                [0, 0],
                [0, .001],
              ],
              localCoordinates: [
                [-25, 25],
                [45, 25],
              ],
            ),
          ],
        ),
        environment: base.environment,
        evidence: base.evidence,
      );
      final frame = SceneFrame.forScene(s);
      final anchor = s.vehicles.single.anchor.worldAnchor;
      final projected = SceneCamera(
        target: frame.target,
        yaw: frame.yaw,
        pitch: frame.pitch,
        distance: frame.span * 1.35,
        viewport: const Size(1000, 700),
      ).project(RenderPoint(anchor.x, anchor.y, anchor.z));
      expect(projected, isNotNull);
      expect(projected!.dx, inInclusiveRange(180, 820));
      expect(projected.dy, inInclusiveRange(135, 620));
      expect(frame.span, lessThan(40));
      expect(frame.pitch, inInclusiveRange(-.9, -.62));
    },
  );
  test(
    'projected foreground obstruction loses to a clear camera candidate',
    () {
      final base = fixtures.scene(evidence: [fixtures.evidence('e')]);
      final old = SceneFrame.forScene(base);
      final midway = RenderPoint(
        (old.eye.x + old.target.x) / 2,
        0,
        (old.eye.z + old.target.z) / 2,
      );
      final obstruction = building(
        tags: {'height': '30'},
        ring: [
          [midway.x - 7, midway.z - 7],
          [midway.x + 7, midway.z - 7],
          [midway.x + 7, midway.z + 7],
          [midway.x - 7, midway.z + 7],
        ],
      );
      final s = fixtures.scene(
        evidence: base.evidence,
        env: environment([obstruction]),
      );
      final frame = SceneFrame.forScene(s);
      final camera = SceneCamera(
        target: frame.target,
        yaw: frame.yaw,
        pitch: frame.pitch,
        distance: frame.span * 1.35,
        viewport: const Size(1000, 700),
      );
      final anchor = s.vehicles.single.anchor.worldAnchor;
      final p = camera.project(RenderPoint(anchor.x, anchor.y, anchor.z));
      final bounds = projectedBuildingBounds(
        camera,
        obstruction.localCoordinates,
        30,
      );
      expect(p, isNotNull);
      expect(bounds?.inflate(5).contains(p!), isFalse);
      expect(frame.yaw, isNot(old.yaw));
    },
  );
  test('camera road visibility score uses genuine nearby road projection', () {
    final s = fixtures.scene(evidence: [fixtures.evidence('e')]);
    final anchor = s.vehicles.single.anchor.worldAnchor;
    final target = RenderPoint(anchor.x, anchor.y, anchor.z);
    final scores = [
      for (final yaw in [.2, .8, 1.4, 2.0])
        visibleNearbyRoadScore(
          SceneCamera(
            target: target,
            yaw: yaw,
            pitch: -.72,
            distance: 30,
            viewport: const Size(1000, 700),
          ),
          s,
          target,
        ),
    ];
    expect(scores.reduce(math.max), greaterThan(scores.reduce(math.min)));
    expect(scores.reduce(math.max), greaterThan(0));
  });
  test('near and viewport clipping keep finite paths bounded', () {
    const c = SceneCamera(
      target: RenderPoint(0, 0, 0),
      yaw: 0,
      pitch: 0,
      distance: 10,
      viewport: Size(400, 300),
    );
    final v = c.clipVisible(const [
      RenderPoint(-1000, -1000, -11),
      RenderPoint(1000, -1000, 1),
      RenderPoint(0, 1000, 1),
    ]);
    expect(v, isNotEmpty);
    for (final p in v) {
      final q = c.screen(p);
      expect(q.dx.isFinite && q.dy.isFinite, isTrue);
      expect(q.dx, inInclusiveRange(-.001, 400.001));
      expect(q.dy, inInclusiveRange(-.001, 300.001));
    }
  });
  test('invalid coordinates and cameras cannot reach a screen path', () {
    const c = SceneCamera(
      target: RenderPoint(0, 0, 0),
      yaw: 0,
      pitch: 0,
      distance: 10,
      viewport: Size(400, 300),
    );
    expect(c.project(const RenderPoint(double.nan, 0, 0)), isNull);
    expect(c.clipVisible(const [RenderPoint(double.infinity, 0, 0)]), isEmpty);
    const bad = SceneCamera(
      target: RenderPoint(0, 0, 0),
      yaw: double.nan,
      pitch: 0,
      distance: 10,
      viewport: Size(400, 300),
    );
    expect(bad.project(const RenderPoint(0, 0, 0)), isNull);
  });
  test('gestures bounded and invalid scale cannot poison camera', () {
    expect(sceneGestureZoom(1, 1.5), 1.5);
    expect(sceneGestureZoom(1, double.nan), 1);
    expect(sceneGestureZoom(1, 10000), 10);
    expect(sceneGestureZoom(1, .00001), .2);
    expect(scenePitch(double.infinity), -.78);
    expect(scenePitch(100), -.12);
    expect(scenePitch(-100), -1.4);
  });
  test('display winding normalization preserves original footprint', () {
    final f = building(),
        saved = f.localCoordinates.map((p) => List<double>.from(p)).toList();
    final a = displayFootprint(f.localCoordinates),
        b = displayFootprint(f.localCoordinates.reversed.toList());
    expect(a.length, 4);
    expect(b.length, 4);
    expect(f.localCoordinates, saved);
  });
  test('road surfaces contrast reference ground with provenance intact', () {
    final data = SceneRenderData(fixtures.scene());
    final road = data.meshes.singleWhere((m) => m.id.startsWith('road/'));
    expect(road.faces.first.color, isNot(data.meshes.first.faces.first.color));
    expect(road.provenance, contains('representational / unknown'));
    expect(data.meshes.first.provenance, contains('Visualization only'));
    expect(data.meshes.first.faces.length, 104);
    final ground = data.meshes.first.faces.expand((f) => f.vertices);
    expect(
      ground.map((p) => (p.x - data.frame.target.x).abs()).reduce(math.max),
      lessThanOrEqualTo(46),
    );
  });
  test('genuine nearby road generates clipped viewport ribbon diagnostics', () {
    final s = fixtures.scene(evidence: [fixtures.evidence('e')]);
    final data = SceneRenderData(s);
    expect(data.roadDiagnostics.sourceRoads, 1);
    expect(data.roadDiagnostics.centerlineSegments, 1);
    expect(data.roadDiagnostics.ribbonPieces, greaterThan(0));
    expect(data.roadDiagnostics.renderFaces, greaterThan(0));
    expect(data.roadDiagnostics.representationalWidths, 1);
    expect(data.roadDiagnostics.nearestEvidenceBucket, isNot('noRoadSegments'));
    final camera = SceneCamera(
      target: data.frame.target,
      yaw: data.frame.yaw,
      pitch: data.frame.pitch,
      distance: data.frame.span * 1.35,
      viewport: const Size(800, 600),
    );
    final faces = projectFaces(data, camera, true);
    expect(faces.where((f) => f.mesh.id.startsWith('road/')), isNotEmpty);
    expect(
      faces.where(
        (f) =>
            f.mesh.id.startsWith('road/') &&
            f.face.vertices.every((p) => (p.y - .14).abs() < .0001),
      ),
      isNotEmpty,
    );
  });
  test('incident reference is a low ring, not physical collision geometry', () {
    final mesh = SceneRenderData(fixtures.scene()).meshes.last;
    expect(mesh.label, 'Incident location reference');
    expect(mesh.provenance, contains('No collision point'));
    expect(
      mesh.faces.expand((f) => f.vertices).every((v) => v.y == .16),
      isTrue,
    );
  });
  test('display motorcycle pivot does not move the analytical anchor', () {
    final s = fixtures.scene(evidence: [fixtures.evidence('e')]),
        vehicle = s.vehicles.single;
    final p = vehicle.anchor.worldAnchor;
    final faces = vehicleFaces(vehicle);
    expect(
      faces
          .expand((f) => f.vertices)
          .map((p) => p.y)
          .reduce((a, b) => a < b ? a : b),
      closeTo(p.y, 1e-6),
    );
    expect(identical(p, vehicle.anchor.worldAnchor), isTrue);
    expect(vehicle.orientation, 'Not established');
    expect(vehicle.dimensions, 'Not measured');
  });
  test(
    'bounded wall subdivision improves long-face sorting without adding source objects',
    () {
      final f = building(),
          s = fixtures.scene(
            env: environment([f]),
            evidence: [fixtures.evidence('e')],
          );
      final data = SceneRenderData(s), second = SceneRenderData(s);
      expect(data.meshes.map((m) => m.id), second.meshes.map((m) => m.id));
      expect(
        data.meshes.where((m) => m.id.startsWith('environment/')),
        hasLength(1),
      );
      final camera = SceneCamera(
        target: data.frame.target,
        yaw: data.frame.yaw,
        pitch: data.frame.pitch,
        distance: data.frame.span * 1.35,
        viewport: const Size(600, 500),
      );
      final faces = projectFaces(data, camera, true);
      for (var i = 1; i < faces.length; i++) {
        expect(faces[i - 1].depth, greaterThanOrEqualTo(faces[i].depth));
      }
    },
  );
  testWidgets(
    'render QA fixture is test-only and contains no generated surroundings',
    (tester) async {
      final base = fixtures.scene(
        evidence: [fixtures.evidence('e')],
        env: environment([
          building(
            tags: {'height': '8', 'building:colour': '#D8C5A3'},
            ring: const [
              [-8, -8],
              [-1, -8],
              [-1, 3],
              [-8, 3],
            ],
          ),
          building(
            ring: const [
              [22, 8],
              [32, 8],
              [32, 20],
              [22, 20],
            ],
          ),
        ]),
      );
      final s = ReconstructionScene(
        caseId: base.caseId,
        location: base.location,
        roads: RoadContext(
          caseId: base.caseId,
          latitude: 0,
          longitude: 0,
          status: 'AVAILABLE',
          retrievedAt: fixtures.date,
          roads: const [
            RoadSegment(
              id: 'qa-real-source-road',
              coordinates: [
                [0, 0],
                [0, .001],
              ],
              localCoordinates: [
                [-25, 25],
                [45, 25],
              ],
            ),
          ],
        ),
        environment: base.environment,
        evidence: base.evidence,
      );
      final data = SceneRenderData(s), key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: key,
            child: CustomPaint(
              painter: ReconstructionPainter(
                data: data,
                yaw: data.frame.yaw,
                pitch: data.frame.pitch,
                zoom: 1,
                pan: Offset.zero,
                evidence: false,
                centerlines: false,
                grid: false,
                environment: true,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.byWidgetPredicate(
                      (widget) =>
                          widget is CustomPaint &&
                          widget.painter is ReconstructionPainter,
                    ),
                  )
                  .painter!
              as ReconstructionPainter;
      expect(painter.submittedRoadFaces, greaterThan(0));
      expect(painter.visibleRoadFaces, greaterThan(0));
      expect(painter.visibleRoadTopFaces, greaterThan(0));
      expect(painter.evidenceAnchorInViewport, isTrue);
      if (const bool.fromEnvironment('IRIS_RENDER_QA')) {
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '../.local-tools/task012j-scene.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    },
  );
}
