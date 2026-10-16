enum ScenarioObservationKind {
  frontDamage('Front-area damage observed'),
  rearDamage('Rear-area damage observed'),
  sideDamage('Side-area damage observed'),
  longitudinalArrangement('Vehicles observed in a longitudinal arrangement'),
  opposingOrientation('Vehicles observed facing opposing directions'),
  crossingArrangement('Vehicles observed in crossing paths/positions'),
  intersectionContext('Incident observed at an intersection'),
  turningPosition('A vehicle observed turning'),
  mergingContext('Vehicles observed in a merge/lane-change context'),
  roadwayDeparture('Vehicle observed outside the roadway'),
  fixedObjectContact('Vehicle contact with a fixed object observed'),
  overturnedVehicle('Vehicle observed overturned'),
  pedestrianConflict('Pedestrian conflict evidence observed'),
  cyclistConflict('Cyclist conflict evidence observed');

  const ScenarioObservationKind(this.label);
  final String label;
}

class ScenarioObservation {
  const ScenarioObservation({
    required this.id,
    required this.caseId,
    required this.evidenceId,
    required this.evidenceSha256,
    required this.kind,
    required this.subjectLabel,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id, caseId, evidenceId, evidenceSha256, subjectLabel, note;
  final ScenarioObservationKind kind;
  final DateTime createdAt, updatedAt;
}

enum ScenarioFamily {
  rearEnd,
  frontal,
  sideImpact,
  intersectionCrossing,
  turningConflict,
  mergingConflict,
  roadwayDeparture,
  fixedObjectCollision,
  overturning,
  pedestrianConflict,
  cyclistConflict,
}

class AccidentScenarioHypothesis {
  const AccidentScenarioHypothesis({
    required this.family,
    required this.title,
    required this.possibleSequence,
    required this.supportingObservationIds,
    required this.supportingEvidenceIds,
    required this.contradictions,
    required this.missingInformation,
    required this.alternatives,
    required this.verificationNeeded,
  });
  final ScenarioFamily family;
  final String title, possibleSequence;
  final List<String> supportingObservationIds, supportingEvidenceIds;
  final List<String> contradictions,
      missingInformation,
      alternatives,
      verificationNeeded;
}

enum ScenarioAnalysisState { available, insufficientEvidence, stale }

class AccidentScenarioAnalysis {
  const AccidentScenarioAnalysis({
    required this.caseId,
    required this.engineVersion,
    required this.inputFingerprint,
    required this.state,
    required this.hypotheses,
    required this.generatedAt,
  });
  final String caseId, engineVersion, inputFingerprint;
  final ScenarioAnalysisState state;
  final List<AccidentScenarioHypothesis> hypotheses;
  final DateTime generatedAt;
}
