import '../../location/domain/case_location.dart';
import '../../location/domain/road_context.dart';
import '../../location/domain/environment_context.dart';
import '../../geometry/domain/relative_geometry.dart';
import '../../geometry/domain/evidence_world_alignment.dart';
import '../../geometry/domain/evidence_vehicle_marker.dart';

enum SceneProvenance {
  mapDerived,
  evidenceDerived,
  userAligned,
  representationalDisplay,
}

/// Renderer-independent source snapshot. No display dimensions or meshes belong
/// here. Relative evidence becomes world placement ONLY through saved user input.
class ReconstructionScene {
  const ReconstructionScene({
    required this.caseId,
    required this.location,
    required this.roads,
    required this.environment,
    required this.evidence,
    this.relatedViews = const [],
  });
  final String caseId;
  final CaseLocation? location;
  final RoadContext? roads;
  final EnvironmentContext? environment;
  final List<SceneEvidence> evidence;
  final List<RelatedViews> relatedViews;
  static const coordinateSystem = 'TASK011 local frame: X east, Y up, Z north';
  static const originLabel = 'Incident location reference';
  // A confirmed origin permits independent building retrieval even when the
  // road provider is unavailable. Evidence alignment still requires roads.
  bool get hasWorld => location != null;
  bool get hasRoadContext =>
      roads?.status == 'AVAILABLE' && roads!.roads.isNotEmpty;
  List<EnvironmentFeature> get environmentFeatures =>
      environment?.hasVerifiedResult == true ? environment!.features : const [];
  Iterable<SceneVehicle> get vehicles => evidence.expand(
    (e) => e.markers.map((m) => SceneVehicle(e.evidenceId, m)),
  );
  Iterable<RelativePoint> get alignedPoints => evidence
      .where((e) => e.geometry != null && e.alignment != null)
      .expand((e) => e.geometry!.points.map(e.alignment!.transform));
  ReconstructionScene withEnvironment(EnvironmentContext? value) =>
      ReconstructionScene(
        caseId: caseId,
        location: location,
        roads: roads,
        environment: value,
        evidence: evidence,
        relatedViews: relatedViews,
      );
}

class SceneEvidence {
  const SceneEvidence({
    required this.evidenceId,
    required this.label,
    required this.capabilities,
    required this.placementStatus,
    this.geometry,
    this.alignment,
    this.markers = const [],
  });
  final String evidenceId, label, placementStatus;
  final Map<String, String> capabilities;
  final RelativeGeometry? geometry;
  final EvidenceWorldAlignment? alignment;
  final List<EvidenceVehicleMarker> markers;
  Set<SceneProvenance> get provenance => {
    SceneProvenance.evidenceDerived,
    if (alignment != null) SceneProvenance.userAligned,
  };
}

class SceneVehicle {
  const SceneVehicle(this.evidenceId, this.anchor);
  final String evidenceId;
  final EvidenceVehicleMarker anchor;
  String get id => '$evidenceId/detection/${anchor.detectionIndex}';
  String get dimensions => 'Not measured';
  String get orientation => 'Not established';
  Set<SceneProvenance> get provenance => {
    SceneProvenance.evidenceDerived,
    SceneProvenance.userAligned,
  };
}

class RelatedViews {
  const RelatedViews(this.evidenceAId, this.evidenceBId, this.inliers);
  final String evidenceAId, evidenceBId;
  final int inliers;
  String get relationship =>
      'Verified epipolar correspondence; object identity and metric pose unresolved';
}
