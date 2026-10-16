import 'evidence_segmentation.dart';

abstract interface class EvidenceSegmentationRepository {
  Future<EvidenceSegmentationAnalysis?> get(String evidenceId);
  Future<void> save(EvidenceSegmentationAnalysis analysis);
}
