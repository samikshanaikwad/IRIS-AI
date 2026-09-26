import '../core/database/iris_database.dart';
import '../features/cases/data/managed_case_repository.dart';
import '../features/cases/data/sqlite_case_repository.dart';
import '../features/cases/domain/case_repository.dart';
import '../features/evidence/application/evidence_acquisition_service.dart';
import '../features/evidence/application/evidence_controller.dart';
import '../features/evidence/data/evidence_storage.dart';
import '../features/evidence/data/sqlite_evidence_repository.dart';
import '../features/evidence/domain/evidence_repository.dart';

class IrisApplicationServices {
  IrisApplicationServices({
    required this.caseRepository,
    this.evidenceRepository,
    this.evidenceStorage,
    this.evidenceAcquisition,
    Future<void> Function()? close,
  }) : _close = close;

  factory IrisApplicationServices.production() {
    final IrisDatabase database = IrisDatabase();
    return IrisApplicationServices.fromDatabase(database);
  }

  factory IrisApplicationServices.fromDatabase(
    IrisDatabase database, {
    EvidenceStorage? evidenceStorage,
  }) {
    final EvidenceStorage storage = evidenceStorage ?? EvidenceStorage();
    final EvidenceRepository evidenceRepository = SqliteEvidenceRepository(
      database,
    );
    return IrisApplicationServices(
      caseRepository: ManagedCaseRepository(
        SqliteCaseRepository(database),
        storage,
      ),
      evidenceRepository: evidenceRepository,
      evidenceStorage: storage,
      evidenceAcquisition: EvidenceAcquisitionService(
        repository: evidenceRepository,
        storage: storage,
      ),
      close: database.close,
    );
  }

  final CaseRepository caseRepository;
  final EvidenceRepository? evidenceRepository;
  final EvidenceStorage? evidenceStorage;
  final EvidenceAcquisitionService? evidenceAcquisition;
  final Future<void> Function()? _close;

  EvidenceController evidenceControllerFor(String caseId) {
    final EvidenceRepository? repository = evidenceRepository;
    final EvidenceStorage? storage = evidenceStorage;
    final EvidenceAcquisitionService? acquisition = evidenceAcquisition;
    if (repository == null || storage == null || acquisition == null) {
      throw StateError('Evidence services are not configured.');
    }
    return EvidenceController(
      caseId: caseId,
      repository: repository,
      storage: storage,
      acquisition: acquisition,
    );
  }

  Future<void> close() async {
    await _close?.call();
  }
}
