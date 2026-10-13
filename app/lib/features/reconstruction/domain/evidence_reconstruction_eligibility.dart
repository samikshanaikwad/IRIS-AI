import '../../detection/domain/evidence_detection.dart';
import '../../geometry/domain/evidence_vehicle_marker.dart';
import '../../geometry/domain/evidence_world_alignment.dart';
import '../../geometry/domain/relative_geometry.dart';

enum ReconstructionPrerequisite {
  ready,
  missing,
  stale,
  invalid,
  unavailable,
  notChecked,
}

enum EvidenceReconstructionState {
  ready,
  missingDetection,
  staleDetection,
  invalidDetection,
  detectionUnavailable,
  noEligibleVehicle,
  missingDepth,
  staleDepth,
  depthUnavailable,
  missingGeometry,
  staleGeometry,
  invalidGeometry,
  geometryUnavailable,
  missingAlignment,
  staleAlignment,
  invalidAlignment,
  alignmentUnavailable,
  missingRequiredWorldContext,
  anchorRegionHasNoPoints,
  anchorGenerationFailed,
}

/// Read-only eligibility result. Contains no display dimensions and no inferred
/// camera/vehicle pose. States never create substitutes for absent source data.
class EvidenceReconstructionEligibility {
  const EvidenceReconstructionEligibility({
    required this.state,
    required this.detectionState,
    required this.depthState,
    required this.geometryState,
    required this.alignmentState,
    required this.worldState,
    required this.eligibleCount,
    required this.classes,
    required this.pointCount,
    required this.anchorAttempted,
    this.markers = const [],
  });
  final EvidenceReconstructionState state;
  final ReconstructionPrerequisite detectionState,
      depthState,
      geometryState,
      alignmentState,
      worldState;
  final int eligibleCount, pointCount;
  final List<String> classes;
  final bool anchorAttempted;
  final List<EvidenceVehicleMarker> markers;
  bool get ready => state == EvidenceReconstructionState.ready;
  String get message => switch (state) {
    EvidenceReconstructionState.ready =>
      'Ready — evidence-derived vehicle included',
    EvidenceReconstructionState.missingDetection =>
      'Waiting for object detection',
    EvidenceReconstructionState.staleDetection =>
      'Object detection stale — review source',
    EvidenceReconstructionState.invalidDetection =>
      'Object detection contract invalid',
    EvidenceReconstructionState.detectionUnavailable =>
      'Object detection unavailable — check quality/source status',
    EvidenceReconstructionState.noEligibleVehicle =>
      'No eligible vehicle detections',
    EvidenceReconstructionState.missingDepth => 'Relative depth missing',
    EvidenceReconstructionState.staleDepth => 'Relative depth stale',
    EvidenceReconstructionState.depthUnavailable =>
      'Relative depth unavailable — check quality/source status',
    EvidenceReconstructionState.missingGeometry => 'Relative geometry missing',
    EvidenceReconstructionState.staleGeometry => 'Relative geometry stale',
    EvidenceReconstructionState.invalidGeometry =>
      'Relative geometry invalid or unreadable',
    EvidenceReconstructionState.geometryUnavailable =>
      'Relative geometry unavailable',
    EvidenceReconstructionState.missingAlignment =>
      'Waiting for user alignment — use Align Evidence',
    EvidenceReconstructionState.staleAlignment =>
      'Saved alignment stale — review in Align Evidence',
    EvidenceReconstructionState.invalidAlignment =>
      'Saved alignment has invalid transform values',
    EvidenceReconstructionState.alignmentUnavailable =>
      'Saved alignment could not be read',
    EvidenceReconstructionState.missingRequiredWorldContext =>
      'Confirmed incident location required to verify saved alignment',
    EvidenceReconstructionState.anchorRegionHasNoPoints =>
      'No valid geometry points in vehicle anchor region',
    EvidenceReconstructionState.anchorGenerationFailed =>
      'Vehicle anchor could not be generated',
  };

  /// Safe for debug logs and user-copyable diagnostics: no IDs, filenames,
  /// coordinates, hashes, transforms or provider payloads.
  String diagnostic(int ordinal) =>
      'E$ordinal detection=${detectionState.name} '
      'eligible=$eligibleCount classes=${classes.join(',')} depth=${depthState.name} '
      'geometry=${geometryState.name} points=$pointCount alignment=${alignmentState.name} '
      'world=${worldState.name} anchorAttempted=$anchorAttempted anchors=${markers.length} '
      'state=${state.name} scene=${ready ? 'INCLUDED' : 'EXCLUDED'}';
}

const _vehicleIds = {
  1: 'bicycle',
  2: 'car',
  3: 'motorcycle',
  5: 'bus',
  7: 'truck',
};
bool isEligibleReconstructionDetection(EvidenceDetection d) =>
    _vehicleIds[d.classId] == d.className &&
    d.score.isFinite &&
    d.score >= .30 &&
    d.score <= 1 &&
    [
      d.xmin,
      d.ymin,
      d.xmax,
      d.ymax,
    ].every((v) => v.isFinite && v >= 0 && v <= 1) &&
    d.xmin < d.xmax &&
    d.ymin < d.ymax;

EvidenceReconstructionEligibility evaluateEvidenceReconstruction({
  required String evidenceId,
  required String evidenceSha256,
  required ReconstructionPrerequisite detectionState,
  required ReconstructionPrerequisite depthState,
  required ReconstructionPrerequisite geometryState,
  required ReconstructionPrerequisite alignmentState,
  required ReconstructionPrerequisite worldState,
  EvidenceDetectionAnalysis? detection,
  RelativeGeometry? geometry,
  EvidenceWorldAlignment? alignment,
}) {
  final eligible =
      detection?.detections.where(isEligibleReconstructionDetection).toList() ??
      <EvidenceDetection>[];
  var attempted = false;
  var markers = <EvidenceVehicleMarker>[];
  EvidenceReconstructionState decide() {
    if (detectionState == ReconstructionPrerequisite.stale) {
      return EvidenceReconstructionState.staleDetection;
    }
    if (detectionState == ReconstructionPrerequisite.missing) {
      return EvidenceReconstructionState.missingDetection;
    }
    if (detectionState != ReconstructionPrerequisite.ready ||
        detection == null) {
      return EvidenceReconstructionState.detectionUnavailable;
    }
    if (detection.evidenceId != evidenceId ||
        detection.evidenceSha256 != evidenceSha256) {
      return EvidenceReconstructionState.invalidDetection;
    }
    if (eligible.isEmpty) return EvidenceReconstructionState.noEligibleVehicle;
    if (depthState == ReconstructionPrerequisite.missing) {
      return EvidenceReconstructionState.missingDepth;
    }
    if (depthState == ReconstructionPrerequisite.stale) {
      return EvidenceReconstructionState.staleDepth;
    }
    if (depthState != ReconstructionPrerequisite.ready &&
        depthState != ReconstructionPrerequisite.notChecked) {
      return EvidenceReconstructionState.depthUnavailable;
    }
    if (geometryState == ReconstructionPrerequisite.stale) {
      return EvidenceReconstructionState.staleGeometry;
    }
    if (geometryState == ReconstructionPrerequisite.missing) {
      return EvidenceReconstructionState.missingGeometry;
    }
    if (geometryState == ReconstructionPrerequisite.invalid) {
      return EvidenceReconstructionState.invalidGeometry;
    }
    if (geometryState != ReconstructionPrerequisite.ready || geometry == null) {
      return EvidenceReconstructionState.geometryUnavailable;
    }
    if (geometry.evidenceId != evidenceId) {
      return EvidenceReconstructionState.invalidGeometry;
    }
    if (alignmentState == ReconstructionPrerequisite.missing) {
      return EvidenceReconstructionState.missingAlignment;
    }
    if (alignmentState == ReconstructionPrerequisite.invalid) {
      return EvidenceReconstructionState.invalidAlignment;
    }
    if (worldState != ReconstructionPrerequisite.ready) {
      return EvidenceReconstructionState.missingRequiredWorldContext;
    }
    if (alignmentState == ReconstructionPrerequisite.stale) {
      return EvidenceReconstructionState.staleAlignment;
    }
    if (alignmentState != ReconstructionPrerequisite.ready ||
        alignment == null) {
      return EvidenceReconstructionState.alignmentUnavailable;
    }
    if (alignment.evidenceId != evidenceId ||
        ![
          alignment.translationX,
          alignment.translationY,
          alignment.translationZ,
          alignment.yaw,
          alignment.uniformScale,
        ].every((v) => v.isFinite) ||
        alignment.uniformScale <= 0) {
      return EvidenceReconstructionState.invalidAlignment;
    }
    attempted = true;
    try {
      // Preserve the TASK012C lower-central, median-depth anchor. Do not broaden
      // the region without a proven case failure. Only current eligible records.
      markers =
          deriveVehicleMarkers(
                analysis: detection,
                geometry: geometry,
                alignment: alignment,
              )
              .where(
                (m) =>
                    isEligibleReconstructionDetection(
                      detection.detections[m.detectionIndex],
                    ) &&
                    [
                      m.worldAnchor.x,
                      m.worldAnchor.y,
                      m.worldAnchor.z,
                    ].every((v) => v.isFinite),
              )
              .toList();
      return markers.isEmpty
          ? EvidenceReconstructionState.anchorRegionHasNoPoints
          : EvidenceReconstructionState.ready;
    } on Object {
      return EvidenceReconstructionState.anchorGenerationFailed;
    }
  }

  final state = decide();
  return EvidenceReconstructionEligibility(
    state: state,
    detectionState: detectionState,
    depthState: depthState,
    geometryState: geometryState,
    alignmentState: alignmentState,
    worldState: worldState,
    eligibleCount: eligible.length,
    classes: eligible.map((d) => d.className).toSet().toList()..sort(),
    pointCount: geometry?.points.length ?? 0,
    anchorAttempted: attempted,
    markers: List.unmodifiable(markers),
  );
}
