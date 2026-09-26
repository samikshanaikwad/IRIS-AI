import 'evidence_quality_assessment.dart';

abstract interface class EvidenceQualityRepository {
  Future<EvidenceQualityAssessment?> getForEvidence(String evidenceId);

  Future<void> save(EvidenceQualityAssessment assessment);
}
