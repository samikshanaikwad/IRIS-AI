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
import '../../depth/domain/evidence_depth.dart';
import '../../multiview/application/multiview_service.dart';
import '../domain/reconstruction_scene.dart';
import '../domain/evidence_reconstruction_eligibility.dart';

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
      var depthState = ReconstructionPrerequisite.notChecked;
      if (depth != null) {
        depthState = ReconstructionPrerequisite.unavailable;
        await stage('Depth', () async {
          final snapshot = await depth!.load(item);
          depthState = switch (snapshot.state) {
            DepthState.analyzed => ReconstructionPrerequisite.ready,
            DepthState.notAnalyzed => ReconstructionPrerequisite.missing,
            DepthState.stale => ReconstructionPrerequisite.stale,
            _ => ReconstructionPrerequisite.unavailable,
          };
          return snapshot.state.name;
        });
      }
      EvidenceDetectionAnalysis? analysis;
      var detectionState = ReconstructionPrerequisite.unavailable;
      await stage('Detection', () async {
        final snapshot = await detection?.load(item);
        if (snapshot?.state == DetectionState.complete) {
          analysis = snapshot!.analysis;
        }
        detectionState = switch (snapshot?.state) {
          DetectionState.complete => ReconstructionPrerequisite.ready,
          DetectionState.notAnalyzed => ReconstructionPrerequisite.missing,
          DetectionState.stale => ReconstructionPrerequisite.stale,
          _ => ReconstructionPrerequisite.unavailable,
        };
        return snapshot?.state.name ?? 'unavailable';
      });
      GeometryRecord? record;
      RelativeGeometry? points;
      var geometryState = ReconstructionPrerequisite.unavailable;
      await stage('Relative geometry', () async {
        final inspector = geometry;
        if (inspector is RelativeGeometryInspectionOperations) {
          final result =
              await (inspector as RelativeGeometryInspectionOperations).inspect(
                item,
              );
          record = result.record;
          points = result.geometry;
          geometryState = ReconstructionPrerequisite.values.byName(
            result.state.name,
          );
          return result.state.name;
        }
        record = await geometry?.load(item);
        if (record == null) return 'absent or stale';
        if (record!.algorithmVersion != 'relative-geometry-v1' ||
            record!.coordinateVersion != 'iris-relative-camera-v1') {
          geometryState = ReconstructionPrerequisite.invalid;
          return 'unsupported contract';
        }
        points = await geometry!.read(record!);
        geometryState = ReconstructionPrerequisite.ready;
        return 'current';
      });
      EvidenceWorldAlignment? saved;
      var alignmentState = ReconstructionPrerequisite.unavailable;
      final worldState =
          roads != null && roads.status == 'AVAILABLE' && roads.roads.isNotEmpty
          ? ReconstructionPrerequisite.ready
          : ReconstructionPrerequisite.missing;
      await stage('World alignment', () async {
        saved = await alignment?.load(item.id);
        capabilities['Alignment record'] = saved == null
            ? 'missing'
            : 'present';
        capabilities['Alignment scale'] = saved == null
            ? 'not available'
            : saved!.uniformScale.isFinite && saved!.uniformScale > 0
            ? 'valid'
            : 'invalid';
        capabilities['Alignment translation'] = saved == null
            ? 'not available'
            : [
                saved!.translationX,
                saved!.translationY,
                saved!.translationZ,
              ].every((v) => v.isFinite)
            ? 'valid'
            : 'invalid';
        if (saved == null) {
          alignmentState = ReconstructionPrerequisite.missing;
          return 'not saved';
        }
        if (![
              saved!.translationX,
              saved!.translationY,
              saved!.translationZ,
              saved!.yaw,
              saved!.uniformScale,
            ].every((v) => v.isFinite) ||
            saved!.uniformScale <= 0 ||
            saved!.evidenceId != item.id ||
            saved!.caseId != caseId) {
          alignmentState = ReconstructionPrerequisite.invalid;
          return 'invalid transform or evidence ownership';
        }
        if (worldState != ReconstructionPrerequisite.ready) {
          return 'unverifiable — current road context required';
        }
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
          alignmentState = ReconstructionPrerequisite.stale;
          return 'stale — review required';
        }
        alignmentState = ReconstructionPrerequisite.ready;
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
          eligibility: evaluateEvidenceReconstruction(
            evidenceId: item.id,
            evidenceSha256: item.sha256,
            detectionState: detectionState,
            depthState: depthState,
            geometryState: geometryState,
            alignmentState: alignmentState,
            worldState: worldState,
            detection: analysis,
            geometry: points,
            alignment: saved,
          ),
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
        for (var i = 0; i < evidence.length; i++) {
          final e = evidence[i];
          await const MethodChannel(
            'com.iris.debug/environment',
          ).invokeMethod<void>('logCounts', {
            'message':
                'stage=evidence ${e.eligibility?.diagnostic(i + 1)} '
                'quality=${e.capabilities['Quality'] ?? 'notChecked'} classification=${e.capabilities['Classification'] ?? 'notChecked'} '
                'alignmentRecord=${e.capabilities['Alignment record']} scale=${e.capabilities['Alignment scale']} translation=${e.capabilities['Alignment translation']} '
                'correspondence=${relations.where((r) => r.evidenceAId == e.evidenceId || r.evidenceBId == e.evidenceId).length}',
          });
        }
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
  EvidenceReconstructionEligibility? eligibility,
}) {
  final valid =
      geometry != null &&
      alignment != null &&
      detection != null &&
      geometry.evidenceId == item.id &&
      alignment.evidenceId == item.id &&
      detection.evidenceId == item.id &&
      detection.evidenceSha256 == item.sha256;
  final markers =
      eligibility?.markers ??
      (valid
          ? deriveVehicleMarkers(
              analysis: detection,
              geometry: geometry,
              alignment: alignment,
            )
          : <EvidenceVehicleMarker>[]);
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
    placementStatus: eligibility?.message ?? status,
    geometry: geometry,
    alignment: alignment,
    markers: List.unmodifiable(markers),
    eligibility: eligibility,
  );
}
