import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'package:iris/features/evidence/data/evidence_storage.dart';
import 'package:iris/features/evidence/domain/evidence_image.dart';
import 'package:iris/features/evidence_quality/application/evidence_quality_controller.dart';
import 'package:iris/features/evidence_quality/application/evidence_quality_service.dart';
import 'package:iris/features/evidence_quality/domain/evidence_quality_assessment.dart';
import 'package:iris/features/evidence_quality/domain/evidence_quality_repository.dart';
import 'package:iris/features/evidence_quality/processing/image_quality_analyzer.dart';

void main() {
  late Directory directory;
  late EvidenceStorage storage;
  late _MemoryQualityRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'iris_quality_application_test_',
    );
    storage = EvidenceStorage(rootProvider: () async => directory);
    repository = _MemoryQualityRepository();
  });

  tearDown(() async {
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  test('successful assessment persists and reloads as current', () async {
    final EvidenceImage evidence = await _writeEvidence(directory, 'one');
    final EvidenceQualityAssessment assessment = _assessment(
      evidence,
      assessedSha256: evidence.sha256,
    );
    final EvidenceQualityService service = EvidenceQualityService(
      repository: repository,
      storage: storage,
      analyzer: _CallbackAnalyzer((_) async => assessment),
    );

    expect(await service.assess(evidence), same(assessment));
    expect(repository.saved[evidence.id], same(assessment));
    final EvidenceQualitySnapshot loaded = await service.load(evidence);
    expect(loaded.state, EvidenceQualitySnapshotState.current);
    expect(loaded.assessment, same(assessment));
  });

  test('changed bytes make a persisted assessment stale', () async {
    final EvidenceImage evidence = await _writeEvidence(directory, 'changed');
    repository.saved[evidence.id] = _assessment(
      evidence,
      assessedSha256: evidence.sha256,
    );
    final EvidenceQualityService service = EvidenceQualityService(
      repository: repository,
      storage: storage,
      analyzer: _CallbackAnalyzer(
        (_) async => throw StateError('Analyzer must not run during load.'),
      ),
    );
    final File managed = File(
      await storage.absolutePath(evidence.storedRelativePath),
    );
    await managed.writeAsBytes(<int>[9, 8, 7], flush: true);

    final EvidenceQualitySnapshot loaded = await service.load(evidence);
    expect(loaded.state, EvidenceQualitySnapshotState.stale);
  });

  test('computation failure does not fabricate or persist a result', () async {
    final EvidenceImage evidence = await _writeEvidence(directory, 'failure');
    final EvidenceQualityService service = EvidenceQualityService(
      repository: repository,
      storage: storage,
      analyzer: _CallbackAnalyzer(
        (_) async => throw StateError('Controlled computation failure.'),
      ),
    );

    await expectLater(service.assess(evidence), throwsStateError);
    expect(repository.saved, isEmpty);
  });

  test('persistence failure is distinguished after real computation', () async {
    final EvidenceImage evidence = await _writeEvidence(directory, 'save-fail');
    repository.failSave = true;
    final EvidenceQualityService service = EvidenceQualityService(
      repository: repository,
      storage: storage,
      analyzer: _CallbackAnalyzer(
        (_) async => _assessment(evidence, assessedSha256: evidence.sha256),
      ),
    );

    await expectLater(
      service.assess(evidence),
      throwsA(isA<EvidenceQualityPersistenceException>()),
    );
    expect(repository.saved, isEmpty);
  });

  test('controller prevents duplicate assessment submissions', () async {
    final EvidenceImage evidence = await _writeEvidence(directory, 'duplicate');
    final Completer<EvidenceQualityAssessment> completer =
        Completer<EvidenceQualityAssessment>();
    final _ControlledOperations operations = _ControlledOperations(
      onAssess: (_) => completer.future,
    );
    final EvidenceQualityController controller = EvidenceQualityController(
      evidence: evidence,
      operations: operations,
    );
    addTearDown(controller.dispose);

    final Future<bool> first = controller.assess();
    expect(controller.assessing, isTrue);
    expect(await controller.assess(), isFalse);
    expect(operations.assessCalls, 1);
    completer.complete(_assessment(evidence, assessedSha256: evidence.sha256));
    expect(await first, isTrue);
    expect(controller.assessing, isFalse);
  });

  test('reassessment replaces the displayed result', () async {
    final EvidenceImage evidence = await _writeEvidence(directory, 'reassess');
    final EvidenceQualityAssessment oldAssessment = _assessment(
      evidence,
      assessedSha256: evidence.sha256,
      readiness: EvidenceReadiness.usableWithLimitations,
    );
    final EvidenceQualityAssessment newAssessment = _assessment(
      evidence,
      assessedSha256: evidence.sha256,
      readiness: EvidenceReadiness.ready,
    );
    final _ControlledOperations operations = _ControlledOperations(
      snapshot: EvidenceQualitySnapshot.current(oldAssessment),
      onAssess: (_) async => newAssessment,
    );
    final EvidenceQualityController controller = EvidenceQualityController(
      evidence: evidence,
      operations: operations,
    );
    addTearDown(controller.dispose);

    await controller.load();
    expect(controller.snapshot.assessment?.readiness, oldAssessment.readiness);
    expect(await controller.assess(), isTrue);
    expect(controller.snapshot.assessment?.readiness, EvidenceReadiness.ready);
  });

  test('one damaged image does not prevent an unrelated assessment', () async {
    final EvidenceImage damaged = await _writeEvidence(directory, 'damaged');
    final EvidenceImage good = await _writeEvidence(directory, 'good');
    final EvidenceQualityService service = EvidenceQualityService(
      repository: repository,
      storage: storage,
      analyzer: _CallbackAnalyzer((EvidenceImage evidence) async {
        if (evidence.id == damaged.id) {
          throw StateError('Controlled damaged image failure.');
        }
        return _assessment(evidence, assessedSha256: evidence.sha256);
      }),
    );

    await expectLater(service.assess(damaged), throwsStateError);
    expect(await service.assess(good), isNotNull);
    expect(repository.saved.keys, <String>[good.id]);
  });
}

class _MemoryQualityRepository implements EvidenceQualityRepository {
  final Map<String, EvidenceQualityAssessment> saved =
      <String, EvidenceQualityAssessment>{};
  bool failSave = false;

  @override
  Future<EvidenceQualityAssessment?> getForEvidence(String evidenceId) async =>
      saved[evidenceId];

  @override
  Future<void> save(EvidenceQualityAssessment assessment) async {
    if (failSave) {
      throw StateError('Controlled persistence failure.');
    }
    saved[assessment.evidenceId] = assessment;
  }
}

class _CallbackAnalyzer implements EvidenceQualityAnalyzer {
  const _CallbackAnalyzer(this.callback);

  final Future<EvidenceQualityAssessment> Function(EvidenceImage evidence)
  callback;

  @override
  Future<EvidenceQualityAssessment> analyze({
    required EvidenceImage evidence,
    required String absolutePath,
  }) => callback(evidence);
}

class _ControlledOperations implements EvidenceQualityOperations {
  _ControlledOperations({
    this.snapshot = const EvidenceQualitySnapshot.notAssessed(),
    required this.onAssess,
  });

  final EvidenceQualitySnapshot snapshot;
  final Future<EvidenceQualityAssessment> Function(EvidenceImage evidence)
  onAssess;
  int assessCalls = 0;

  @override
  Future<EvidenceQualityAssessment> assess(EvidenceImage evidence) {
    assessCalls++;
    return onAssess(evidence);
  }

  @override
  Future<EvidenceQualitySnapshot> load(EvidenceImage evidence) async =>
      snapshot;
}

Future<EvidenceImage> _writeEvidence(Directory root, String id) async {
  final String relativePath = path.join(
    'cases',
    'case-id',
    'evidence',
    '$id.bin',
  );
  final File file = File(path.join(root.path, relativePath));
  await file.parent.create(recursive: true);
  await file.writeAsBytes(id.codeUnits, flush: true);
  final String digest = sha256.convert(await file.readAsBytes()).toString();
  return EvidenceImage(
    id: id,
    caseId: 'case-id',
    storedRelativePath: relativePath,
    source: EvidenceSource.gallery,
    importedAt: DateTime.utc(2026, 9, 27),
    fileSizeBytes: await file.length(),
    sha256: digest,
  );
}

EvidenceQualityAssessment _assessment(
  EvidenceImage evidence, {
  required String assessedSha256,
  EvidenceReadiness readiness = EvidenceReadiness.ready,
}) => EvidenceQualityAssessment(
  evidenceId: evidence.id,
  assessedAt: DateTime.utc(2026, 9, 27),
  algorithmVersion: FlutterImageQualityAnalyzer.algorithmVersion,
  expectedSha256: evidence.sha256,
  assessedSha256: assessedSha256,
  fileState: EvidenceFileState.available,
  decodeState: EvidenceDecodeState.decoded,
  integrityState: EvidenceIntegrityState.verified,
  readiness: readiness,
  fileSizeBytes: evidence.fileSizeBytes,
  originalWidth: 1280,
  originalHeight: 720,
  analysisWidth: 1024,
  analysisHeight: 576,
  orientation: EvidenceOrientation.landscape,
  sharpnessValue: 150,
  meanLuminance: 128,
  darkClippedFraction: 0,
  brightClippedFraction: 0,
  findings: const <EvidenceQualityFinding>[],
);
