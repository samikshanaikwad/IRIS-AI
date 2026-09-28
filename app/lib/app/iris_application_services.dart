import '../core/database/iris_database.dart';
import '../features/cases/data/managed_case_repository.dart';
import '../features/cases/data/sqlite_case_repository.dart';
import '../features/cases/domain/case_repository.dart';
import '../features/evidence/application/evidence_acquisition_service.dart';
import '../features/evidence/application/evidence_controller.dart';
import '../features/evidence/data/evidence_storage.dart';
import '../features/evidence/data/sqlite_evidence_repository.dart';
import '../features/evidence/domain/evidence_image.dart';
import '../features/evidence/domain/evidence_repository.dart';
import '../features/evidence_quality/application/evidence_quality_controller.dart';
import '../features/evidence_quality/application/evidence_quality_service.dart';
import '../features/evidence_quality/data/sqlite_evidence_quality_repository.dart';
import '../features/evidence_quality/domain/evidence_quality_repository.dart';
import '../features/evidence_quality/processing/image_quality_analyzer.dart';
import '../features/classification/application/evidence_classification_controller.dart';
import '../features/classification/application/evidence_classification_service.dart';
import '../features/classification/data/sqlite_evidence_classification_repository.dart';
import '../features/classification/domain/evidence_classification_repository.dart';

class IrisApplicationServices {
  IrisApplicationServices({
    required this.caseRepository,
    this.evidenceRepository,
    this.evidenceStorage,
    this.evidenceAcquisition,
    this.evidenceQualityRepository,
    this.evidenceQuality,
    this.evidenceClassification,
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
    final EvidenceQualityRepository qualityRepository =
        SqliteEvidenceQualityRepository(database);
    final EvidenceQualityService qualityService = EvidenceQualityService(
      repository: qualityRepository,
      storage: storage,
      analyzer: FlutterImageQualityAnalyzer(),
    );
    final EvidenceClassificationRepository classificationRepository =
        SqliteEvidenceClassificationRepository(database);
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
      evidenceQualityRepository: qualityRepository,
      evidenceQuality: qualityService,
      evidenceClassification: EvidenceClassificationService(
        repository: classificationRepository,
        storage: storage,
        quality: qualityService,
      ),
      close: database.close,
    );
  }

  final CaseRepository caseRepository;
  final EvidenceRepository? evidenceRepository;
  final EvidenceStorage? evidenceStorage;
  final EvidenceAcquisitionService? evidenceAcquisition;
  final EvidenceQualityRepository? evidenceQualityRepository;
  final EvidenceQualityOperations? evidenceQuality;
  final EvidenceClassificationOperations? evidenceClassification;
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

  EvidenceQualityController evidenceQualityControllerFor(
    EvidenceImage evidence,
  ) {
    final EvidenceQualityOperations? operations = evidenceQuality;
    if (operations == null) {
      throw StateError('Evidence quality services are not configured.');
    }
    return EvidenceQualityController(
      evidence: evidence,
      operations: operations,
    );
  }

  EvidenceClassificationController evidenceClassificationControllerFor(
    EvidenceImage evidence,
  ) {
    final EvidenceClassificationOperations? operations = evidenceClassification;
    if (operations == null) {
      throw StateError('Classification services are not configured.');
    }
    return EvidenceClassificationController(
      evidence: evidence,
      operations: operations,
    );
  }

  Future<void> close() async {
    await _close?.call();
  }
}
