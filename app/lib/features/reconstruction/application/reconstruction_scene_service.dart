import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import '../../evidence/domain/evidence_image.dart';
import '../../location/application/case_location_service.dart';
import '../../location/domain/road_context.dart';
import '../../geometry/application/relative_geometry_service.dart';
import '../../geometry/application/evidence_world_alignment_service.dart';
import '../../geometry/domain/evidence_vehicle_marker.dart';
import '../../geometry/domain/relative_geometry.dart';
import '../../geometry/data/sqlite_geometry_repository.dart';
import '../../geometry/domain/evidence_world_alignment.dart';
import '../../detection/application/evidence_detection_service.dart';
import '../../detection/domain/evidence_detection.dart';
import '../../evidence_quality/application/evidence_quality_service.dart';
import '../../classification/application/evidence_classification_service.dart';
import '../../depth/application/evidence_depth_service.dart';
import '../../multiview/application/multiview_service.dart';
import '../domain/reconstruction_scene.dart';

class ReconstructionSceneService {
  ReconstructionSceneService({
    required this.location,
    required this.loadEvidence,
    this.geometry,
    this.alignment,
    this.detection,
    this.quality,
    this.classification,
    this.depth,
    this.multiView,
  });
  final CaseLocationService location;
  final Future<List<EvidenceImage>> Function() loadEvidence;
  final RelativeGeometryOperations? geometry;
  final EvidenceWorldAlignmentService? alignment;
  final EvidenceDetectionOperations? detection;
  final EvidenceQualityOperations? quality;
  final EvidenceClassificationOperations? classification;
  final EvidenceDepthOperations? depth;
  final MultiViewService? multiView;

  Future<ReconstructionScene> load(String caseId) async {
    final origin = await location.load(caseId);
    final roads = await location.loadRoadContext(caseId);
    final environment = await location.loadEnvironment(caseId);
    final images = await loadEvidence();
    final evidence = <SceneEvidence>[];
    for (final item in images.where((e) => e.caseId == caseId)) {
      final capabilities = <String, String>{};
      Future<void> stage(String name, Future<String> Function() run) async {
        try {
          capabilities[name] = await run();
        } on Object {
          capabilities[name] = 'unavailable — source read failed';
        }
      }

      if (quality != null) {
        await stage(
          'Quality',
          () async => (await quality!.load(item)).state.name,
        );
      }
      if (classification != null) {
        await stage(
          'Classification',
          () async => (await classification!.load(item)).state.name,
        );
      }
      if (depth != null) {
        await stage('Depth', () async => (await depth!.load(item)).state.name);
      }
      EvidenceDetectionAnalysis? analysis;
      await stage('Detection', () async {
        final snapshot = await detection?.load(item);
        if (snapshot?.state == DetectionState.complete) {
          analysis = snapshot!.analysis;
        }
        return snapshot?.state.name ?? 'unavailable';
      });
      GeometryRecord? record;
      RelativeGeometry? points;
      await stage('Relative geometry', () async {
        record = await geometry?.load(item);
        if (record == null) return 'absent or stale';
        if (record!.algorithmVersion != 'relative-geometry-v1' ||
            record!.coordinateVersion != 'iris-relative-camera-v1') {
          return 'unsupported contract';
        }
        points = await geometry!.read(record!);
        return 'current';
      });
      EvidenceWorldAlignment? saved;
      await stage('World alignment', () async {
        saved = await alignment?.load(item.id);
        if (saved == null) return 'not saved';
        if (saved!.caseId != caseId ||
            roads == null ||
            roads.status != 'AVAILABLE' ||
            roads.roads.isEmpty ||
            record == null ||
            saved!.isStale(
              geometrySha256: record!.sha256,
              roadContextFingerprint: roadFingerprint(roads),
            ) ||
            ![
              saved!.translationX,
              saved!.translationY,
              saved!.translationZ,
              saved!.yaw,
              saved!.uniformScale,
            ].every((v) => v.isFinite) ||
            saved!.uniformScale <= 0) {
          saved = null;
          return 'stale — review required';
        }
        return 'user supplied / uncalibrated';
      });
      if (capabilities['World alignment'] != 'user supplied / uncalibrated') {
        saved = null;
      }
      evidence.add(
        composeSceneEvidence(
          item: item,
          capabilities: capabilities,
          geometry: points,
          alignment: saved,
          detection: analysis,
        ),
      );
    }
    final relations = multiView == null
        ? <RelatedViews>[]
        : await multiView!.repository.currentRelatedViews(caseId, images);
    final current = await location.load(caseId);
    if (current?.latitude != origin?.latitude ||
        current?.longitude != origin?.longitude) {
      throw StateError(
        'Confirmed location changed during scene loading; reopen scene',
      );
    }
    if (kDebugMode) {
      try {
        await const MethodChannel(
          'com.iris.debug/environment',
        ).invokeMethod<void>('logCounts', {
          'message':
              'stage=scene evidence=${evidence.length} '
              'aligned=${evidence.where((e) => e.geometry != null && e.alignment != null).length} '
              'vehicles=${evidence.fold<int>(0, (n, e) => n + e.markers.length)} '
              'buildings=${environment?.count('building') ?? 0} '
              'trees=${environment?.count('tree') ?? 0} barriers=${environment?.count('barrier') ?? 0} '
              'environment=${environment?.providerState.storageValue ?? 'UNAVAILABLE'}',
        });
      } on MissingPluginException {
        // Test/non-Android host has no optional diagnostics bridge.
      } on PlatformException {
        // Diagnostics must not alter scene availability.
      }
    }
    return ReconstructionScene(
      caseId: caseId,
      location: origin,
      roads: roads,
      environment: environment,
      evidence: evidence,
      relatedViews: relations,
    );
  }
}

String roadFingerprint(RoadContext roads) => sha256
    .convert(
      utf8.encode(
        '${roads.caseId}|${roads.latitude}|${roads.longitude}|${roads.status}|${roads.json}',
      ),
    )
    .toString();

SceneEvidence composeSceneEvidence({
  required EvidenceImage item,
  required Map<String, String> capabilities,
  RelativeGeometry? geometry,
  EvidenceWorldAlignment? alignment,
  EvidenceDetectionAnalysis? detection,
}) {
  final valid =
      geometry != null &&
      alignment != null &&
      detection != null &&
      geometry.evidenceId == item.id &&
      alignment.evidenceId == item.id &&
      detection.evidenceId == item.id &&
      detection.evidenceSha256 == item.sha256;
  final markers = valid
      ? deriveVehicleMarkers(
          analysis: detection,
          geometry: geometry,
          alignment: alignment,
        )
      : <EvidenceVehicleMarker>[];
  final status = geometry == null
      ? 'Current relative geometry unavailable'
      : alignment == null
      ? 'Saved alignment absent or stale — review alignment'
      : detection == null
      ? 'Current object detection unavailable'
      : markers.isEmpty
      ? 'No eligible detection with a valid relative anchor'
      : '${markers.length} evidence-anchored representation(s)';
  return SceneEvidence(
    evidenceId: item.id,
    label: item.originalDisplayName ?? 'Evidence',
    capabilities: Map.unmodifiable(capabilities),
    placementStatus: status,
    geometry: geometry,
    alignment: alignment,
    markers: List.unmodifiable(markers),
  );
}
