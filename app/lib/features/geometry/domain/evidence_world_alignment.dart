import '../../../core/domain/case_local_world.dart';
import 'relative_geometry.dart';

enum AlignmentSource { userSupplied }

enum AlignmentProvenanceStatus {
  current,
  legacyCurrentRoadProven,
  geometryChanged,
  worldFrameChanged,
  legacyLocationUnproven,
  unsupportedContract;

  bool get usable =>
      this == AlignmentProvenanceStatus.current ||
      this == AlignmentProvenanceStatus.legacyCurrentRoadProven;
}

class EvidenceWorldAlignment {
  const EvidenceWorldAlignment({
    required this.caseId,
    required this.evidenceId,
    required this.translationX,
    required this.translationY,
    required this.translationZ,
    required this.yaw,
    required this.uniformScale,
    required this.source,
    required this.geometrySha256,
    required this.roadContextFingerprint,
    this.worldFrameFingerprint,
    this.provenanceVersion,
    required this.createdAt,
    required this.updatedAt,
  });

  final String caseId, evidenceId, geometrySha256, roadContextFingerprint;
  final String? worldFrameFingerprint, provenanceVersion;
  final double translationX, translationY, translationZ, yaw, uniformScale;
  final AlignmentSource source;
  final DateTime createdAt, updatedAt;

  static const currentProvenanceVersion = 'task012-alignment-provenance-v2';

  AlignmentProvenanceStatus provenanceStatus({
    required String geometrySha256,
    required String roadContextFingerprint,
    required String worldFrameFingerprint,
  }) {
    if (this.geometrySha256 != geometrySha256) {
      return AlignmentProvenanceStatus.geometryChanged;
    }
    final storedFrame = this.worldFrameFingerprint;
    if (storedFrame != null) {
      if (provenanceVersion != currentProvenanceVersion) {
        return AlignmentProvenanceStatus.unsupportedContract;
      }
      return storedFrame == worldFrameFingerprint
          ? AlignmentProvenanceStatus.current
          : AlignmentProvenanceStatus.worldFrameChanged;
    }
    // A legacy full-road fingerprint can prove applicability only while the
    // exact historical road snapshot remains current. A mismatch is ambiguous:
    // it may be a same-location refresh or a different origin, so review is
    // mandatory and the transform is never silently resurrected.
    if (provenanceVersion != null) {
      return AlignmentProvenanceStatus.unsupportedContract;
    }
    return this.roadContextFingerprint == roadContextFingerprint
        ? AlignmentProvenanceStatus.legacyCurrentRoadProven
        : AlignmentProvenanceStatus.legacyLocationUnproven;
  }

  RelativePoint transform(RelativePoint point) {
    final world = CaseLocalWorldFrame.alignRelative(
      relativeX: point.x,
      relativeY: point.y,
      relativeZ: point.z,
      translationX: translationX,
      translationY: translationY,
      translationZ: translationZ,
      yaw: yaw,
      uniformScale: uniformScale,
    );
    return RelativePoint(
      x: world.xEast,
      y: world.yUp,
      z: world.zNorth,
      u: point.u,
      v: point.v,
    );
  }
}
