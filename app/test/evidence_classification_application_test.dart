import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'package:iris/features/classification/application/evidence_classification_service.dart';
import 'package:iris/features/classification/domain/evidence_classification.dart';
import 'package:iris/features/classification/domain/evidence_classification_repository.dart';
import 'package:iris/features/evidence/data/evidence_storage.dart';
import 'package:iris/features/evidence/domain/evidence_image.dart';
import 'package:iris/features/evidence_quality/application/evidence_quality_service.dart';
import 'package:iris/features/evidence_quality/domain/evidence_quality_assessment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('com.iris.classifier/v1');
  late Directory directory;
  late EvidenceImage evidence;
  late _MemoryRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('iris_classification_');
    final File file = File(
      path.join(directory.path, 'cases/case/evidence/item.jpg'),
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(<int>[1, 2, 3]);
    evidence = EvidenceImage(
      id: 'item',
      caseId: 'case',
      storedRelativePath: 'cases/case/evidence/item.jpg',
      source: EvidenceSource.gallery,
      importedAt: DateTime.utc(2026),
      fileSizeBytes: 3,
      sha256: sha256.convert(<int>[1, 2, 3]).toString(),
    );
    repository = _MemoryRepository();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (MethodCall call) async => <String, Object?>{
            'rawLogit': 2.0,
            'modelSha256': EvidenceClassificationService.modelSha256,
          },
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  test(
    'ready evidence runs actual gateway result and persists per evidence',
    () async {
      final EvidenceClassificationService service = buildService(
        directory,
        repository,
        EvidenceQualitySnapshot.current(_assessment(evidence)),
      );
      final EvidenceClassification value = await service.analyze(evidence);
      expect(value.rawLogit, 2.0);
      expect(
        value.modelScore,
        greaterThan(EvidenceClassificationService.threshold),
      );
      expect(value.label, EvidenceClassificationLabel.accident);
      expect(repository.value?.evidenceId, evidence.id);
    },
  );

  test('not assessed evidence is blocked without invoking inference', () async {
    final EvidenceClassificationService service = buildService(
      directory,
      repository,
      const EvidenceQualitySnapshot.notAssessed(),
    );
    await expectLater(
      service.analyze(evidence),
      throwsA(isA<ClassificationUnavailableException>()),
    );
    expect(repository.value, isNull);
  });
}

EvidenceClassificationService buildService(
  Directory directory,
  EvidenceClassificationRepository repository,
  EvidenceQualitySnapshot snapshot,
) => EvidenceClassificationService(
  repository: repository,
  storage: EvidenceStorage(rootProvider: () async => directory),
  quality: _QualityOperations(snapshot),
);

class _MemoryRepository implements EvidenceClassificationRepository {
  EvidenceClassification? value;
  @override
  Future<EvidenceClassification?> getForEvidence(String evidenceId) async =>
      value;
  @override
  Future<void> save(EvidenceClassification classification) async =>
      value = classification;
}

class _QualityOperations implements EvidenceQualityOperations {
  const _QualityOperations(this.snapshot);
  final EvidenceQualitySnapshot snapshot;
  @override
  Future<EvidenceQualitySnapshot> load(EvidenceImage evidence) async =>
      snapshot;
  @override
  Future<EvidenceQualityAssessment> assess(EvidenceImage evidence) =>
      throw UnimplementedError();
}

EvidenceQualityAssessment _assessment(EvidenceImage evidence) =>
    EvidenceQualityAssessment(
      evidenceId: evidence.id,
      assessedAt: DateTime.utc(2026),
      algorithmVersion: 'iris-image-quality-v1',
      expectedSha256: evidence.sha256,
      assessedSha256: evidence.sha256,
      fileState: EvidenceFileState.available,
      decodeState: EvidenceDecodeState.decoded,
      integrityState: EvidenceIntegrityState.verified,
      readiness: EvidenceReadiness.ready,
      findings: const <EvidenceQualityFinding>[],
    );
