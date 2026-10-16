import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../detection/application/evidence_detection_service.dart';
import '../../detection/domain/evidence_detection.dart';
import '../../evidence/domain/evidence_image.dart';
import '../../evidence/domain/evidence_repository.dart';
import '../domain/accident_scenario.dart';
import '../domain/accident_scenario_repository.dart';

abstract interface class AccidentScenarioOperations {
  Future<ScenarioWorkspace> load(String caseId);
  Future<void> addObservation({
    required String caseId,
    required EvidenceImage evidence,
    required ScenarioObservationKind kind,
    required String subjectLabel,
    required String note,
  });
  Future<void> deleteObservation(String id);
  Future<AccidentScenarioAnalysis> generate(String caseId);
}

class ScenarioWorkspace {
  const ScenarioWorkspace({
    required this.evidence,
    required this.observations,
    required this.analysis,
  });
  final List<EvidenceImage> evidence;
  final List<ScenarioObservation> observations;
  final AccidentScenarioAnalysis? analysis;
}

class AccidentScenarioService implements AccidentScenarioOperations {
  AccidentScenarioService({
    required AccidentScenarioRepository repository,
    required EvidenceRepository evidence,
    required EvidenceDetectionOperations detection,
    DateTime Function()? clock,
  }) : _repository = repository,
       _evidence = evidence,
       _detection = detection,
       _clock = clock ?? DateTime.now;

  static const String engineVersion = 'iris-scenario-rules-v1';
  static const Set<String> _vehicleClasses = {
    'car',
    'motorcycle',
    'bus',
    'truck',
    'bicycle',
  };
  final AccidentScenarioRepository _repository;
  final EvidenceRepository _evidence;
  final EvidenceDetectionOperations _detection;
  final DateTime Function() _clock;
  int _observationSequence = 0;

  @override
  Future<ScenarioWorkspace> load(String caseId) async {
    final evidence = await _evidence.getForCase(caseId);
    final observations = await _repository.observations(caseId);
    final currentFingerprint = await _fingerprint(evidence, observations);
    final stored = await _repository.analysis(caseId);
    final analysis = stored == null
        ? null
        : stored.inputFingerprint == currentFingerprint &&
              stored.engineVersion == engineVersion
        ? stored
        : AccidentScenarioAnalysis(
            caseId: stored.caseId,
            engineVersion: stored.engineVersion,
            inputFingerprint: stored.inputFingerprint,
            state: ScenarioAnalysisState.stale,
            hypotheses: stored.hypotheses,
            generatedAt: stored.generatedAt,
          );
    return ScenarioWorkspace(
      evidence: evidence,
      observations: observations,
      analysis: analysis,
    );
  }

  @override
  Future<void> addObservation({
    required String caseId,
    required EvidenceImage evidence,
    required ScenarioObservationKind kind,
    required String subjectLabel,
    required String note,
  }) async {
    final EvidenceImage? persisted = await _evidence.getById(evidence.id);
    if (persisted == null ||
        persisted.caseId != caseId ||
        persisted.sha256 != evidence.sha256) {
      throw StateError('Observation evidence does not belong to this case.');
    }
    final subject = subjectLabel.trim();
    final explanation = note.trim();
    if (subject.isEmpty || explanation.isEmpty) {
      throw ArgumentError('A subject and observation note are required.');
    }
    final now = _clock().toUtc();
    await _repository.saveObservation(
      ScenarioObservation(
        id: 'scenario-observation-${now.microsecondsSinceEpoch}-${_observationSequence++}',
        caseId: caseId,
        evidenceId: evidence.id,
        evidenceSha256: evidence.sha256,
        kind: kind,
        subjectLabel: subject,
        note: explanation,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  @override
  Future<void> deleteObservation(String id) =>
      _repository.deleteObservation(id);

  @override
  Future<AccidentScenarioAnalysis> generate(String caseId) async {
    final evidence = await _evidence.getForCase(caseId);
    final observations = await _repository.observations(caseId);
    final facts = await _facts(evidence, observations);
    final hypotheses = _evaluate(facts);
    final value = AccidentScenarioAnalysis(
      caseId: caseId,
      engineVersion: engineVersion,
      inputFingerprint: await _fingerprint(evidence, observations),
      state: hypotheses.isEmpty
          ? ScenarioAnalysisState.insufficientEvidence
          : ScenarioAnalysisState.available,
      hypotheses: hypotheses,
      generatedAt: _clock().toUtc(),
    );
    await _repository.saveAnalysis(value);
    return value;
  }

  Future<_ScenarioFacts> _facts(
    List<EvidenceImage> evidence,
    List<ScenarioObservation> observations,
  ) async {
    var vehicles = 0;
    var persons = 0;
    var bicycles = 0;
    for (final item in evidence) {
      final snapshot = await _detection.load(item);
      if (snapshot.state != DetectionState.complete) continue;
      for (final detection in snapshot.analysis!.detections) {
        if (_vehicleClasses.contains(detection.className)) vehicles++;
        if (detection.className == 'person') persons++;
        if (detection.className == 'bicycle') bicycles++;
      }
    }
    final current = observations
        .where((observation) {
          return evidence.any(
            (item) =>
                item.id == observation.evidenceId &&
                item.sha256 == observation.evidenceSha256,
          );
        })
        .toList(growable: false);
    return _ScenarioFacts(current, vehicles, persons, bicycles);
  }

  Future<String> _fingerprint(
    List<EvidenceImage> evidence,
    List<ScenarioObservation> observations,
  ) async {
    final evidenceParts = <String>[];
    for (final item in [...evidence]..sort((a, b) => a.id.compareTo(b.id))) {
      final detection = await _detection.load(item);
      final analysis = detection.analysis;
      evidenceParts.add(
        [
          item.id,
          item.sha256,
          detection.state.name,
          analysis?.id ?? '',
          analysis?.evidenceSha256 ?? '',
          ...(analysis?.detections.map(
                (d) =>
                    '${d.classId}:${d.className}:${d.score}:${d.xmin}:${d.ymin}:${d.xmax}:${d.ymax}',
              ) ??
              const Iterable<String>.empty()),
        ].join('|'),
      );
    }
    final observationParts =
        ([...observations]..sort((a, b) => a.id.compareTo(b.id))).map(
          (o) =>
              '${o.id}|${o.evidenceId}|${o.evidenceSha256}|${o.kind.name}|${o.subjectLabel}|${o.note}|${o.updatedAt.toUtc().toIso8601String()}',
        );
    return sha256
        .convert(
          utf8.encode([...evidenceParts, ...observationParts].join('\n')),
        )
        .toString();
  }

  List<AccidentScenarioHypothesis> _evaluate(_ScenarioFacts facts) {
    final result = <AccidentScenarioHypothesis>[];
    bool has(ScenarioObservationKind kind) => facts.has(kind);
    void add({
      required ScenarioFamily family,
      required String title,
      required String sequence,
      required Set<ScenarioObservationKind> support,
      List<String> contradictions = const [],
      required List<String> missing,
      required List<String> alternatives,
      required List<String> verify,
    }) {
      final matched = facts.observations
          .where((o) => support.contains(o.kind))
          .toList(growable: false);
      result.add(
        AccidentScenarioHypothesis(
          family: family,
          title: title,
          possibleSequence: sequence,
          supportingObservationIds: matched.map((o) => o.id).toList(),
          supportingEvidenceIds: matched
              .map((o) => o.evidenceId)
              .toSet()
              .toList(),
          contradictions: contradictions,
          missingInformation: missing,
          alternatives: alternatives,
          verificationNeeded: verify,
        ),
      );
    }

    if (facts.vehicles >= 2 &&
        has(ScenarioObservationKind.frontDamage) &&
        has(ScenarioObservationKind.rearDamage) &&
        has(ScenarioObservationKind.longitudinalArrangement) &&
        !has(ScenarioObservationKind.opposingOrientation)) {
      add(
        family: ScenarioFamily.rearEnd,
        title: 'Possible rear-end vehicle interaction',
        sequence:
            'One vehicle may have contacted the rear area of another while the vehicles were longitudinally arranged.',
        support: {
          ScenarioObservationKind.frontDamage,
          ScenarioObservationKind.rearDamage,
          ScenarioObservationKind.longitudinalArrangement,
        },
        missing: const [
          'Vehicle motion before contact',
          'Impact timing and speed',
          'Independent scene measurements',
        ],
        alternatives: const [
          'Damage may pre-date this incident',
          'Vehicle positions may have changed after the event',
        ],
        verify: const [
          'Additional scene photographs',
          'Vehicle damage examination',
          'Video or witness evidence',
        ],
      );
    }
    if (facts.vehicles >= 2 &&
        facts.count(ScenarioObservationKind.frontDamage) >= 2 &&
        has(ScenarioObservationKind.opposingOrientation)) {
      add(
        family: ScenarioFamily.frontal,
        title: 'Possible frontal vehicle interaction',
        sequence:
            'Two vehicles may have interacted at their front areas while observed in opposing orientations.',
        support: {
          ScenarioObservationKind.frontDamage,
          ScenarioObservationKind.opposingOrientation,
        },
        missing: const [
          'Pre-impact paths',
          'Impact direction',
          'Vehicle speeds',
        ],
        alternatives: const ['One or both damage areas may be unrelated'],
        verify: const [
          'Damage compatibility inspection',
          'Scene measurements',
          'Additional viewpoints',
        ],
      );
    }
    if (facts.vehicles >= 2 &&
        has(ScenarioObservationKind.sideDamage) &&
        has(ScenarioObservationKind.frontDamage) &&
        has(ScenarioObservationKind.crossingArrangement)) {
      add(
        family: has(ScenarioObservationKind.intersectionContext)
            ? ScenarioFamily.intersectionCrossing
            : ScenarioFamily.sideImpact,
        title: has(ScenarioObservationKind.intersectionContext)
            ? 'Possible intersection crossing-path interaction'
            : 'Possible side-impact interaction',
        sequence:
            'A vehicle front area may have interacted with the side area of another while their observed positions crossed.',
        support: {
          ScenarioObservationKind.sideDamage,
          ScenarioObservationKind.frontDamage,
          ScenarioObservationKind.crossingArrangement,
          if (has(ScenarioObservationKind.intersectionContext))
            ScenarioObservationKind.intersectionContext,
        },
        missing: const [
          'Right of way',
          'Signal state',
          'Vehicle motion and timing',
        ],
        alternatives: const ['Observed positions may be post-event positions'],
        verify: const [
          'Traffic-control records',
          'Video or witness evidence',
          'Damage compatibility inspection',
        ],
      );
    }
    if (facts.vehicles >= 1 && has(ScenarioObservationKind.roadwayDeparture)) {
      add(
        family: ScenarioFamily.roadwayDeparture,
        title: 'Possible single-vehicle roadway departure',
        sequence:
            'A vehicle may have departed the roadway before reaching the observed off-road position.',
        support: {ScenarioObservationKind.roadwayDeparture},
        missing: const [
          'Departure path',
          'Reason for departure',
          'Vehicle speed',
        ],
        alternatives: const [
          'The vehicle may have been moved after the incident',
        ],
        verify: const [
          'Road-edge marks',
          'Additional scene photographs',
          'Witness or video evidence',
        ],
      );
    }
    if (facts.vehicles >= 1 &&
        has(ScenarioObservationKind.fixedObjectContact)) {
      add(
        family: ScenarioFamily.fixedObjectCollision,
        title: 'Possible collision with a fixed object',
        sequence: 'A vehicle may have contacted the observed fixed object.',
        support: {ScenarioObservationKind.fixedObjectContact},
        missing: const ['Contact timing', 'Approach path', 'Impact speed'],
        alternatives: const ['Contact evidence may be unrelated to this event'],
        verify: const [
          'Object and vehicle damage compatibility',
          'Scene measurements',
        ],
      );
    }
    if (facts.vehicles >= 1 && has(ScenarioObservationKind.overturnedVehicle)) {
      add(
        family: ScenarioFamily.overturning,
        title: 'Possible overturning sequence',
        sequence:
            'The vehicle may have overturned before reaching its observed resting orientation.',
        support: {ScenarioObservationKind.overturnedVehicle},
        missing: const [
          'Initiating event',
          'Pre-event motion',
          'Rollover path',
        ],
        alternatives: const [
          'The observed orientation may have changed during recovery',
        ],
        verify: const [
          'Scene marks',
          'Vehicle examination',
          'Witness or video evidence',
        ],
      );
    }
    if (facts.vehicles >= 2 &&
        has(ScenarioObservationKind.turningPosition) &&
        has(ScenarioObservationKind.sideDamage)) {
      add(
        family: ScenarioFamily.turningConflict,
        title: 'Possible turning conflict',
        sequence:
            'A turning vehicle may have entered the path of another vehicle before a side-area interaction.',
        support: {
          ScenarioObservationKind.turningPosition,
          ScenarioObservationKind.sideDamage,
        },
        missing: const [
          'Signal use',
          'Right of way',
          'Vehicle motion and timing',
        ],
        alternatives: const ['Observed turning position may be post-event'],
        verify: const ['Video or witness evidence', 'Traffic-control records'],
      );
    }
    if (facts.vehicles >= 2 &&
        has(ScenarioObservationKind.mergingContext) &&
        has(ScenarioObservationKind.sideDamage)) {
      add(
        family: ScenarioFamily.mergingConflict,
        title: 'Possible lane-change or merging conflict',
        sequence:
            'The vehicles may have interacted while their observed paths converged during a merge or lane change.',
        support: {
          ScenarioObservationKind.mergingContext,
          ScenarioObservationKind.sideDamage,
        },
        missing: const [
          'Lane positions before contact',
          'Signals and blind-spot visibility',
        ],
        alternatives: const ['Side damage may have another origin'],
        verify: const [
          'Video evidence',
          'Vehicle damage compatibility',
          'Road-lane measurements',
        ],
      );
    }
    if (facts.vehicles >= 1 &&
        facts.persons >= 1 &&
        has(ScenarioObservationKind.pedestrianConflict)) {
      add(
        family: ScenarioFamily.pedestrianConflict,
        title: 'Possible vehicle–pedestrian conflict',
        sequence:
            'A vehicle and pedestrian may have occupied conflicting paths.',
        support: {ScenarioObservationKind.pedestrianConflict},
        missing: const [
          'Movement sequence',
          'Contact confirmation',
          'Traffic-control state',
        ],
        alternatives: const ['Detected people may be bystanders'],
        verify: const [
          'Witness or video evidence',
          'Medical and scene records',
        ],
      );
    }
    if (facts.vehicles >= 1 &&
        facts.bicycles >= 1 &&
        has(ScenarioObservationKind.cyclistConflict)) {
      add(
        family: ScenarioFamily.cyclistConflict,
        title: 'Possible vehicle–cyclist conflict',
        sequence:
            'A motor vehicle and cyclist may have occupied conflicting paths.',
        support: {ScenarioObservationKind.cyclistConflict},
        missing: const [
          'Movement sequence',
          'Contact confirmation',
          'Traffic-control state',
        ],
        alternatives: const ['Detected bicycle may not have been involved'],
        verify: const [
          'Witness or video evidence',
          'Damage compatibility inspection',
        ],
      );
    }
    return result.take(3).toList(growable: false);
  }
}

class _ScenarioFacts {
  const _ScenarioFacts(
    this.observations,
    this.vehicles,
    this.persons,
    this.bicycles,
  );
  final List<ScenarioObservation> observations;
  final int vehicles, persons, bicycles;
  bool has(ScenarioObservationKind kind) =>
      observations.any((o) => o.kind == kind);
  int count(ScenarioObservationKind kind) =>
      observations.where((o) => o.kind == kind).length;
}
