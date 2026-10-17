import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import '../../../core/domain/case_local_world.dart';
import '../../evidence/domain/evidence_image.dart';
import '../../location/application/case_location_service.dart';
import '../../location/domain/road_context.dart';
import '../../location/domain/environment_context.dart';
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
import '../../partial_surface/application/evidence_partial_surface_service.dart';
import '../../partial_surface/domain/evidence_partial_surface.dart';
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
    this.partialSurfaces,
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
  final EvidencePartialSurfaceOperations? partialSurfaces;

  Future<ReconstructionScene> load(String caseId) async {
    final origin = await location.load(caseId);
    final roads = await location.loadRoadContext(caseId);
    final environment = await location.loadEnvironment(caseId);
    final worldFrameFingerprint = origin == null
        ? null
        : CaseLocalWorldFrame.fingerprint(
            caseId: caseId,
            originLatitude: origin.latitude,
            originLongitude: origin.longitude,
          );
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
      var visibleSurfaces = <EvidencePartialSurfaceMesh>[];
      if (partialSurfaces != null) {
        await stage('Visible partial surface', () async {
          final snapshot = await partialSurfaces!.load(item);
          if (snapshot.state != EvidencePartialSurfaceState.current ||
              snapshot.analysis == null) {
            return snapshot.state.name;
          }
          visibleSurfaces = List<EvidencePartialSurfaceMesh>.unmodifiable(
            await Future.wait(
              snapshot.analysis!.parts.map(partialSurfaces!.read),
            ),
          );
          return 'current (${visibleSurfaces.length} part${visibleSurfaces.length == 1 ? '' : 's'})';
        });
      }
      EvidenceWorldAlignment? saved;
      var alignmentState = ReconstructionPrerequisite.unavailable;
      // The confirmed location defines the canonical TASK012 world frame.
      // Mutable provider road coverage is scene context, not frame identity.
      final worldState = worldFrameFingerprint != null
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
        if (worldState != ReconstructionPrerequisite.ready ||
            worldFrameFingerprint == null) {
          return 'unverifiable — confirmed location required';
        }
        if (record == null) {
          saved = null;
          alignmentState = ReconstructionPrerequisite.stale;
          capabilities['Alignment geometry provenance'] = 'unverifiable';
          capabilities['Alignment world-frame provenance'] = 'unverifiable';
          capabilities['Alignment road snapshot'] = 'unverifiable';
          return 'stale — source geometry unavailable';
        }
        final currentRoadFingerprint = roads == null
            ? null
            : roadFingerprint(roads);
        capabilities['Alignment geometry provenance'] =
            saved!.geometrySha256 == record!.sha256 ? 'current' : 'changed';
        capabilities['Alignment road snapshot'] = currentRoadFingerprint == null
            ? 'unavailable'
            : saved!.roadContextFingerprint == currentRoadFingerprint
            ? 'current'
            : 'changed';
        final provenance = saved!.provenanceStatus(
          geometrySha256: record!.sha256,
          roadContextFingerprint: currentRoadFingerprint ?? '',
          worldFrameFingerprint: worldFrameFingerprint,
        );
        capabilities['Alignment world-frame provenance'] = provenance.name;
        if (!provenance.usable) {
          saved = null;
          alignmentState = ReconstructionPrerequisite.stale;
          return switch (provenance) {
            AlignmentProvenanceStatus.geometryChanged =>
              'stale — evidence geometry changed; review required',
            AlignmentProvenanceStatus.worldFrameChanged =>
              'stale — confirmed location frame changed; review required',
            AlignmentProvenanceStatus.legacyLocationUnproven =>
              'stale — legacy location provenance unproven; review required',
            _ => 'stale — alignment provenance unsupported; review required',
          };
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
          partialSurfaces: visibleSurfaces,
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
        if (environment?.hasVerifiedResult == true) {
          await const MethodChannel(
            'com.iris.debug/environment',
          ).invokeMethod<void>('logCounts', {
            'message':
                'stage=appearance ${buildingAppearanceCounts(environment!.features).entries.map((e) => '${e.key}=${e.value}').join(' ')}',
          });
        }
        for (var i = 0; i < evidence.length; i++) {
          final e = evidence[i];
          await const MethodChannel(
            'com.iris.debug/environment',
          ).invokeMethod<void>('logCounts', {
            'message':
                'stage=evidence ${e.eligibility?.diagnostic(i + 1)} '
                'quality=${e.capabilities['Quality'] ?? 'notChecked'} classification=${e.capabilities['Classification'] ?? 'notChecked'} '
                'alignmentRecord=${e.capabilities['Alignment record']} scale=${e.capabilities['Alignment scale']} translation=${e.capabilities['Alignment translation']} '
                'geometryProvenance=${e.capabilities['Alignment geometry provenance'] ?? 'notChecked'} '
                'worldFrameProvenance=${e.capabilities['Alignment world-frame provenance'] ?? 'notChecked'} '
                'roadSnapshot=${e.capabilities['Alignment road snapshot'] ?? 'notChecked'} '
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
              'partialSurfaces=${evidence.fold<int>(0, (n, e) => n + e.partialSurfaces.length)} '
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
  List<EvidencePartialSurfaceMesh> partialSurfaces = const [],
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
    partialSurfaces: List.unmodifiable(partialSurfaces),
    eligibility: eligibility,
  );
}
