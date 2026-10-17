import 'evidence_partial_surface.dart';

abstract interface class EvidencePartialSurfaceRepository {
  Future<EvidencePartialSurfaceAnalysis?> get(String evidenceId);
  Future<void> save(EvidencePartialSurfaceAnalysis analysis);
}
