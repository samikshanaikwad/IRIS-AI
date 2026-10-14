import '../../evidence/domain/image_coordinate_contract.dart';

enum DepthState { notAnalyzed, analyzing, analyzed, stale, failed, unavailable }

class EvidenceDepthAnalysis {
  const EvidenceDepthAnalysis({
    required this.evidenceId,
    required this.evidenceSha256,
    required this.artifactSha256,
    required this.analyzedAt,
    required this.width,
    required this.height,
    required this.depthWidth,
    required this.depthHeight,
    required this.depthPath,
    required this.min,
    required this.max,
    required this.mean,
    this.inferenceMs,
    this.coordinateMetadata,
  });
  final String evidenceId, evidenceSha256, artifactSha256, depthPath;
  final DateTime analyzedAt;
  final int width, height, depthWidth, depthHeight;
  final double min, max, mean;
  final int? inferenceMs;
  final ImageCoordinateMetadata? coordinateMetadata;
}

class EvidenceDepthSnapshot {
  const EvidenceDepthSnapshot(this.state, {this.analysis, this.message});
  final DepthState state;
  final EvidenceDepthAnalysis? analysis;
  final String? message;
}
