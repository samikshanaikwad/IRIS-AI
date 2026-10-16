import '../../evidence/domain/image_coordinate_contract.dart';

abstract final class EvidenceSegmentationModel {
  static const String id = 'mobilesam-vit-t-task007-box-v1';
  static const String sourceCommit = 'f706ad9c4eb7f219c00d9050e46328518ffb65d2';
  static const String checkpointSha256 =
      '6dbb90523a35330fedd7f1d3dfc66f995213d81b29a5ca8108dbcdd4e37d6c2f';
  static const String encoderSha256 =
      'f55b0f6c6949d4737ba06ddf14b99b35ae7c26c782f9865078e34b0a0f45df49';
  static const String decoderSha256 =
      '4a3d6ee977ce5ad077e1ab980db5f1bffb96758c4029a2abccd0d08634a8bf63';
  static const String runtimeLifecycle =
      'SEQUENTIAL_ENCODER_DECODER_RELEASE_AFTER_RUN';
  static const Map<int, String> supportedClasses = <int, String>{
    2: 'car',
    3: 'motorcycle',
  };
}

class EvidenceSegmentationMask {
  const EvidenceSegmentationMask({
    required this.id,
    required this.detectionIndex,
    required this.classId,
    required this.className,
    required this.detectionScore,
    required this.promptLeft,
    required this.promptTop,
    required this.promptRight,
    required this.promptBottom,
    required this.maskFileRelativePath,
    required this.maskSha256,
    required this.maskPixelCount,
    this.predictedQuality,
  });

  final String id;
  final int detectionIndex;
  final int classId;
  final String className;
  final double detectionScore;
  final double promptLeft, promptTop, promptRight, promptBottom;
  final String maskFileRelativePath, maskSha256;
  final int maskPixelCount;
  final double? predictedQuality;
}

class EvidenceSegmentationAnalysis {
  const EvidenceSegmentationAnalysis({
    required this.id,
    required this.evidenceId,
    required this.caseId,
    required this.sourceEvidenceSha256,
    required this.detectionAnalysisId,
    required this.detectorSha256,
    required this.detectorContractVersion,
    required this.modelId,
    required this.modelSourceCommit,
    required this.modelCheckpointSha256,
    required this.encoderSha256,
    required this.decoderSha256,
    required this.coordinateMetadata,
    required this.analyzedAt,
    required this.overlayFileRelativePath,
    required this.overlaySha256,
    required this.masks,
    this.encoderMs,
    this.decoderMs,
    this.totalMs,
    this.sampledPeakPssKb,
    this.baselinePssKb,
  });

  final String id, evidenceId, caseId, sourceEvidenceSha256;
  final String detectionAnalysisId, detectorSha256, detectorContractVersion;
  final String modelId, modelSourceCommit, modelCheckpointSha256;
  final String encoderSha256, decoderSha256;
  final ImageCoordinateMetadata coordinateMetadata;
  final DateTime analyzedAt;
  final String overlayFileRelativePath, overlaySha256;
  final List<EvidenceSegmentationMask> masks;
  final double? encoderMs, decoderMs, totalMs;
  final int? sampledPeakPssKb, baselinePssKb;
}

enum EvidenceSegmentationState {
  notAnalyzed,
  queued,
  running,
  current,
  stale,
  unsupported,
  unavailable,
  cancelled,
  error,
}

class EvidenceSegmentationSnapshot {
  const EvidenceSegmentationSnapshot(this.state, {this.analysis, this.message});

  final EvidenceSegmentationState state;
  final EvidenceSegmentationAnalysis? analysis;
  final String? message;
}

bool isCurrentSegmentationModel(EvidenceSegmentationAnalysis analysis) =>
    analysis.modelId == EvidenceSegmentationModel.id &&
    analysis.modelSourceCommit == EvidenceSegmentationModel.sourceCommit &&
    analysis.modelCheckpointSha256 ==
        EvidenceSegmentationModel.checkpointSha256 &&
    analysis.encoderSha256 == EvidenceSegmentationModel.encoderSha256 &&
    analysis.decoderSha256 == EvidenceSegmentationModel.decoderSha256 &&
    analysis.coordinateMetadata.contractVersion ==
        IrisImageCoordinateContract.version;
