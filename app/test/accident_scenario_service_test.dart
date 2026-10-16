import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/detection/application/evidence_detection_service.dart';
import 'package:iris/features/detection/domain/evidence_detection.dart';
import 'package:iris/features/evidence/domain/evidence_image.dart';
import 'package:iris/features/evidence/domain/evidence_repository.dart';
import 'package:iris/features/scenarios/application/accident_scenario_service.dart';
import 'package:iris/features/scenarios/domain/accident_scenario.dart';
import 'package:iris/features/scenarios/domain/accident_scenario_repository.dart';

void main() {
  late _ScenarioRepository repository;
  late _EvidenceRepository evidenceRepository;
  late _Detection detection;
  late AccidentScenarioService service;
  late EvidenceImage e1;
  late EvidenceImage e2;

  setUp(() {
    repository = _ScenarioRepository();
    e1 = _evidence('e1', 'a' * 64);
    e2 = _evidence('e2', 'b' * 64);
    evidenceRepository = _EvidenceRepository([e1, e2]);
    detection = _Detection({
      'e1': _complete('e1', e1.sha256, 'car'),
      'e2': _complete('e2', e2.sha256, 'motorcycle'),
    });
    service = AccidentScenarioService(
      repository: repository,
      evidence: evidenceRepository,
      detection: detection,
      clock: () => DateTime.utc(2026, 10, 16),
    );
  });

  test('missing observations produces honest insufficient evidence', () async {
    final analysis = await service.generate('case-1');
    expect(analysis.state, ScenarioAnalysisState.insufficientEvidence);
    expect(analysis.hypotheses, isEmpty);
  });

  test('distinct observation patterns produce distinct scenarios', () async {
    await _add(service, e1, ScenarioObservationKind.roadwayDeparture);
    var analysis = await service.generate('case-1');
    expect(analysis.hypotheses.single.family, ScenarioFamily.roadwayDeparture);

    repository.observationValues.clear();
    await _add(service, e1, ScenarioObservationKind.fixedObjectContact);
    analysis = await service.generate('case-1');
    expect(
      analysis.hypotheses.single.family,
      ScenarioFamily.fixedObjectCollision,
    );
  });

  test(
    'rear-end requires two real detections and all supporting observations',
    () async {
      await _add(service, e1, ScenarioObservationKind.frontDamage);
      await _add(service, e2, ScenarioObservationKind.rearDamage);
      await _add(service, e1, ScenarioObservationKind.longitudinalArrangement);
      final analysis = await service.generate('case-1');
      expect(analysis.hypotheses.single.family, ScenarioFamily.rearEnd);
      expect(
        analysis.hypotheses.single.supportingEvidenceIds,
        containsAll(['e1', 'e2']),
      );
      expect(
        analysis.hypotheses.single.missingInformation,
        contains('Impact timing and speed'),
      );
    },
  );

  test(
    'contradictory opposing orientation rejects rear-end hypothesis',
    () async {
      await _add(service, e1, ScenarioObservationKind.frontDamage);
      await _add(service, e2, ScenarioObservationKind.rearDamage);
      await _add(service, e1, ScenarioObservationKind.longitudinalArrangement);
      await _add(service, e2, ScenarioObservationKind.opposingOrientation);
      final analysis = await service.generate('case-1');
      expect(
        analysis.hypotheses.where((h) => h.family == ScenarioFamily.rearEnd),
        isEmpty,
      );
    },
  );

  test('analysis becomes stale when supporting observation changes', () async {
    await _add(service, e1, ScenarioObservationKind.roadwayDeparture);
    await service.generate('case-1');
    await _add(service, e1, ScenarioObservationKind.frontDamage);
    final workspace = await service.load('case-1');
    expect(workspace.analysis!.state, ScenarioAnalysisState.stale);
  });

  test('stale evidence SHA excludes user observation', () async {
    repository.observationValues.add(
      ScenarioObservation(
        id: 'stale',
        caseId: 'case-1',
        evidenceId: e1.id,
        evidenceSha256: 'f' * 64,
        kind: ScenarioObservationKind.roadwayDeparture,
        subjectLabel: 'vehicle A',
        note: 'Visible outside road boundary.',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );
    final analysis = await service.generate('case-1');
    expect(analysis.state, ScenarioAnalysisState.insufficientEvidence);
  });

  test('observation requires a current persisted evidence reference', () async {
    final forged = _evidence('missing-evidence', 'c' * 64);
    await expectLater(
      _add(service, forged, ScenarioObservationKind.roadwayDeparture),
      throwsStateError,
    );
    expect(repository.observationValues, isEmpty);
  });

  test('unsupported observation pattern cannot create a conclusion', () async {
    await _add(service, e1, ScenarioObservationKind.sideDamage);
    final analysis = await service.generate('case-1');
    expect(analysis.state, ScenarioAnalysisState.insufficientEvidence);
    expect(analysis.hypotheses, isEmpty);
  });

  test('no scenario contains probability, fault, or asserted speed', () async {
    await _add(service, e1, ScenarioObservationKind.roadwayDeparture);
    final analysis = await service.generate('case-1');
    final text = analysis.hypotheses
        .map((h) => '${h.title} ${h.possibleSequence}')
        .join(' ')
        .toLowerCase();
    expect(text, isNot(contains('%')));
    expect(text, isNot(contains('fault')));
    expect(text, isNot(contains(' km/h')));
  });
}

Future<void> _add(
  AccidentScenarioService service,
  EvidenceImage evidence,
  ScenarioObservationKind kind,
) => service.addObservation(
  caseId: 'case-1',
  evidence: evidence,
  kind: kind,
  subjectLabel: 'vehicle ${evidence.id}',
  note: 'Visible in the selected evidence.',
);

EvidenceImage _evidence(String id, String hash) => EvidenceImage(
  id: id,
  caseId: 'case-1',
  storedRelativePath: '$id.jpg',
  source: EvidenceSource.gallery,
  importedAt: DateTime.utc(2026),
  fileSizeBytes: 10,
  sha256: hash,
);

EvidenceDetectionSnapshot _complete(String id, String hash, String className) =>
    EvidenceDetectionSnapshot(
      DetectionState.complete,
      analysis: EvidenceDetectionAnalysis(
        id: 'analysis-$id',
        evidenceId: id,
        evidenceSha256: hash,
        detectorSha256: 'd' * 64,
        thresholdPolicyVersion: 'v1',
        analyzedAt: DateTime.utc(2026),
        inferenceMs: 1,
        detections: [
          EvidenceDetection(
            classId: className == 'car' ? 2 : 3,
            className: className,
            score: .8,
            ymin: .1,
            xmin: .1,
            ymax: .9,
            xmax: .9,
          ),
        ],
      ),
    );

class _EvidenceRepository implements EvidenceRepository {
  _EvidenceRepository(this.values);
  final List<EvidenceImage> values;
  @override
  Future<List<EvidenceImage>> getForCase(String caseId) async => values;
  @override
  Future<EvidenceImage?> getById(String id) async =>
      values.where((e) => e.id == id).firstOrNull;
  @override
  Future<EvidenceImage> add(EvidenceImage evidence) =>
      throw UnimplementedError();
  @override
  Future<bool> delete(String id) => throw UnimplementedError();
  @override
  Future<EvidenceImage?> findDuplicate({
    required String caseId,
    required String sha256,
  }) => throw UnimplementedError();
}

class _Detection implements EvidenceDetectionOperations {
  _Detection(this.values);
  final Map<String, EvidenceDetectionSnapshot> values;
  @override
  Future<EvidenceDetectionSnapshot> load(EvidenceImage e) async =>
      values[e.id] ??
      const EvidenceDetectionSnapshot(DetectionState.notAnalyzed);
  @override
  Future<EvidenceDetectionAnalysis> analyze(EvidenceImage e) =>
      throw UnimplementedError();
}

class _ScenarioRepository implements AccidentScenarioRepository {
  final List<ScenarioObservation> observationValues = [];
  AccidentScenarioAnalysis? analysisValue;
  @override
  Future<AccidentScenarioAnalysis?> analysis(String caseId) async =>
      analysisValue;
  @override
  Future<void> deleteObservation(String id) async =>
      observationValues.removeWhere((o) => o.id == id);
  @override
  Future<List<ScenarioObservation>> observations(String caseId) async =>
      List.of(observationValues);
  @override
  Future<void> saveAnalysis(AccidentScenarioAnalysis value) async =>
      analysisValue = value;
  @override
  Future<void> saveObservation(ScenarioObservation value) async =>
      observationValues.add(value);
}
