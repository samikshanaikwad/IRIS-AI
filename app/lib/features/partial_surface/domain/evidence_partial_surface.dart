import '../../evidence/domain/image_coordinate_contract.dart';

/// Relative, visible-only reconstruction from a current segmentation mask and
/// relative depth.  Its x/y/z values are deliberately uncalibrated and cannot
/// be treated as measurements, vehicle dimensions, or physics inputs.
abstract final class EvidencePartialSurfaceProcessing {
  static const String version = 'iris-visible-surface-v1';
  static const String coordinateSystem =
      'image-relative depth coordinates; nonmetric and uncalibrated';
  static const int maxVerticesPerPart = 4096;
  static const int maxTrianglesPerPart = 8192;
}

class PartialSurfaceVertex {
  const PartialSurfaceVertex({
    required this.x,
    required this.y,
    required this.z,
    required this.u,
    required this.v,
    required this.argb,
  });

  final double x, y, z, u, v;

  /// Original evidence pixel colour sampled in the oriented raster.
  final int argb;
}

class PartialSurfaceTriangle {
  const PartialSurfaceTriangle(this.a, this.b, this.c);
  final int a, b, c;
}

class EvidencePartialSurfacePart {
  const EvidencePartialSurfacePart({
    required this.id,
    required this.segmentationMaskId,
    required this.detectionIndex,
    required this.classId,
    required this.className,
    required this.maskSha256,
    required this.meshFileRelativePath,
    required this.meshSha256,
    required this.vertexCount,
    required this.triangleCount,
  });

  final String id, segmentationMaskId, className, maskSha256;
  final String meshFileRelativePath, meshSha256;
  final int detectionIndex, classId, vertexCount, triangleCount;
}

class EvidencePartialSurfaceAnalysis {
  const EvidencePartialSurfaceAnalysis({
    required this.id,
    required this.evidenceId,
    required this.caseId,
    required this.sourceEvidenceSha256,
    required this.segmentationAnalysisId,
    required this.segmentationFingerprint,
    required this.depthEvidenceSha256,
    required this.depthAnalyzedAt,
    required this.depthModelSha256,
    required this.depthFileSha256,
    required this.coordinateMetadata,
    required this.processingVersion,
    required this.generatedAt,
    required this.parts,
    this.totalMs,
    this.sampledPeakPssKb,
    this.baselinePssKb,
  });

  final String id, evidenceId, caseId, sourceEvidenceSha256;
  final String segmentationAnalysisId, segmentationFingerprint;
  final String depthEvidenceSha256, depthModelSha256, depthFileSha256;
  final DateTime depthAnalyzedAt, generatedAt;
  final ImageCoordinateMetadata coordinateMetadata;
  final String processingVersion;
  final List<EvidencePartialSurfacePart> parts;
  final double? totalMs;
  final int? sampledPeakPssKb, baselinePssKb;
}

class EvidencePartialSurfaceMesh {
  const EvidencePartialSurfaceMesh({
    required this.part,
    required this.vertices,
    required this.triangles,
  });

  final EvidencePartialSurfacePart part;
  final List<PartialSurfaceVertex> vertices;
  final List<PartialSurfaceTriangle> triangles;
}

enum EvidencePartialSurfaceState {
  notGenerated,
  generating,
  current,
  stale,
  missingSegmentation,
  missingDepth,
  unavailable,
  insufficientEvidence,
  cancelled,
  error,
}

class EvidencePartialSurfaceSnapshot {
  const EvidencePartialSurfaceSnapshot(
    this.state, {
    this.analysis,
    this.message,
  });

  final EvidencePartialSurfaceState state;
  final EvidencePartialSurfaceAnalysis? analysis;
  final String? message;
}
