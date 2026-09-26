import '../../evidence/data/evidence_storage.dart';
import '../domain/case_repository.dart';
import '../domain/incident_case.dart';

class ManagedCaseRepository implements CaseRepository {
  ManagedCaseRepository(this._delegate, this._storage);

  final CaseRepository _delegate;
  final EvidenceStorage _storage;

  @override
  Future<IncidentCase> createCase({required String title}) =>
      _delegate.createCase(title: title);

  @override
  Future<bool> deleteCase(String id) async {
    final StagedDeletion staged = await _storage.stageCaseDirectory(id);
    try {
      final bool deleted = await _delegate.deleteCase(id);
      if (!deleted) {
        await staged.restore();
        return false;
      }
      await staged.finalize();
      return true;
    } on Object {
      await staged.restore();
      rethrow;
    }
  }

  @override
  Future<IncidentCase?> getCaseById(String id) => _delegate.getCaseById(id);

  @override
  Future<List<IncidentCase>> getCases({int? limit}) =>
      _delegate.getCases(limit: limit);

  @override
  Future<IncidentCase> renameCase({
    required String id,
    required String title,
  }) => _delegate.renameCase(id: id, title: title);
}
