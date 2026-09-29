import 'dart:math' as math;

import 'relative_geometry.dart';

enum AlignmentSource { userSupplied }

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
    required this.createdAt,
    required this.updatedAt,
  });

  final String caseId, evidenceId, geometrySha256, roadContextFingerprint;
  final double translationX, translationY, translationZ, yaw, uniformScale;
  final AlignmentSource source;
  final DateTime createdAt, updatedAt;

  bool isStale({
    required String geometrySha256,
    required String roadContextFingerprint,
  }) =>
      this.geometrySha256 != geometrySha256 ||
      this.roadContextFingerprint != roadContextFingerprint;

  RelativePoint transform(RelativePoint point) {
    final x = point.x * uniformScale;
    final y = point.y * uniformScale;
    final z = point.z * uniformScale;
    final c = math.cos(yaw), s = math.sin(yaw);
    return RelativePoint(
      x: x * c - z * s + translationX,
      y: y + translationY,
      z: x * s + z * c + translationZ,
      u: point.u,
      v: point.v,
    );
  }
}
