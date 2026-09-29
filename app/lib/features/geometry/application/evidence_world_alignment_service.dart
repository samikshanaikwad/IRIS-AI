import '../data/sqlite_world_alignment_repository.dart';
import '../domain/evidence_world_alignment.dart';

class EvidenceWorldAlignmentService {
  EvidenceWorldAlignmentService({required this.repository});
  final SqliteWorldAlignmentRepository repository;
  Future<EvidenceWorldAlignment?> load(String evidenceId) =>
      repository.get(evidenceId);
  Future<void> save(EvidenceWorldAlignment value) => repository.save(value);
}
