import 'evidence_image.dart';

abstract interface class EvidenceRepository {
  Future<EvidenceImage> add(EvidenceImage evidence);

  Future<List<EvidenceImage>> getForCase(String caseId);

  Future<EvidenceImage?> getById(String id);

  Future<EvidenceImage?> findDuplicate({
    required String caseId,
    required String sha256,
  });

  Future<bool> delete(String id);
}

class DuplicateEvidenceException implements Exception {
  const DuplicateEvidenceException(this.existingEvidenceId);

  final String existingEvidenceId;
}
