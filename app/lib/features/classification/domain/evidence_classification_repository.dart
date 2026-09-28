import 'evidence_classification.dart';

abstract interface class EvidenceClassificationRepository {
  Future<EvidenceClassification?> getForEvidence(String evidenceId);
  Future<void> save(EvidenceClassification classification);
}
