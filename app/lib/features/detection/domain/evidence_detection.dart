import '../../evidence/domain/image_coordinate_contract.dart';

class EvidenceDetection {
  const EvidenceDetection({
    required this.classId,
    required this.className,
    required this.score,
    required this.ymin,
    required this.xmin,
    required this.ymax,
    required this.xmax,
  });
  final int classId;
  final String className;
  final double score;
  final double ymin, xmin, ymax, xmax;
}

class EvidenceDetectionAnalysis {
  const EvidenceDetectionAnalysis({
    required this.id,
    required this.evidenceId,
    required this.evidenceSha256,
    required this.detectorSha256,
    required this.thresholdPolicyVersion,
    required this.analyzedAt,
    required this.inferenceMs,
    required this.detections,
    this.coordinateMetadata,
  });
  final String id, evidenceId, evidenceSha256, detectorSha256;
  final String thresholdPolicyVersion;
  final DateTime analyzedAt;
  final int? inferenceMs;
  final List<EvidenceDetection> detections;
  final ImageCoordinateMetadata? coordinateMetadata;
}

enum DetectionState {
  notAnalyzed,
  detecting,
  complete,
  stale,
  unavailable,
  error,
}

class EvidenceDetectionSnapshot {
  const EvidenceDetectionSnapshot(this.state, {this.analysis, this.message});
  final DetectionState state;
  final EvidenceDetectionAnalysis? analysis;
  final String? message;
}
