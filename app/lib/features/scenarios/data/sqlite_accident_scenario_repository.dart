import 'dart:convert';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_constants.dart';
import '../../../core/database/iris_database.dart';
import '../domain/accident_scenario.dart';
import '../domain/accident_scenario_repository.dart';

class SqliteAccidentScenarioRepository implements AccidentScenarioRepository {
  SqliteAccidentScenarioRepository(this._database);
  final IrisDatabase _database;

  @override
  Future<List<ScenarioObservation>> observations(String caseId) async {
    final db = await _database.open();
    final rows = await db.query(
      IrisDatabaseConstants.scenarioObservationsTable,
      where: 'case_id = ?',
      whereArgs: [caseId],
      orderBy: 'created_at, id',
    );
    return rows.map(_observation).toList(growable: false);
  }

  @override
  Future<void> saveObservation(ScenarioObservation value) async {
    final db = await _database.open();
    await db.insert(
      IrisDatabaseConstants.scenarioObservationsTable,
      {
        'id': value.id,
        'case_id': value.caseId,
        'evidence_id': value.evidenceId,
        'evidence_sha256': value.evidenceSha256,
        'kind': value.kind.name,
        'subject_label': value.subjectLabel,
        'note': value.note,
        'provenance': 'USER_ENTERED',
        'created_at': value.createdAt.millisecondsSinceEpoch,
        'updated_at': value.updatedAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  @override
  Future<void> deleteObservation(String id) async {
    final db = await _database.open();
    await db.delete(
      IrisDatabaseConstants.scenarioObservationsTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<AccidentScenarioAnalysis?> analysis(String caseId) async {
    final db = await _database.open();
    final rows = await db.query(
      IrisDatabaseConstants.scenarioAnalysesTable,
      where: 'case_id = ?',
      whereArgs: [caseId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final raw = jsonDecode(row['hypotheses_json']! as String) as List;
    return AccidentScenarioAnalysis(
      caseId: caseId,
      engineVersion: row['engine_version']! as String,
      inputFingerprint: row['input_fingerprint']! as String,
      state: row['status'] == 'AVAILABLE'
          ? ScenarioAnalysisState.available
          : ScenarioAnalysisState.insufficientEvidence,
      hypotheses: raw
          .map((value) => _hypothesis(Map<String, Object?>.from(value as Map)))
          .toList(growable: false),
      generatedAt: DateTime.fromMillisecondsSinceEpoch(
        row['generated_at']! as int,
        isUtc: true,
      ),
    );
  }

  @override
  Future<void> saveAnalysis(AccidentScenarioAnalysis value) async {
    final db = await _database.open();
    await db.insert(
      IrisDatabaseConstants.scenarioAnalysesTable,
      {
        'case_id': value.caseId,
        'engine_version': value.engineVersion,
        'input_fingerprint': value.inputFingerprint,
        'status': value.state == ScenarioAnalysisState.available
            ? 'AVAILABLE'
            : 'INSUFFICIENT_EVIDENCE',
        'hypotheses_json': jsonEncode(
          value.hypotheses.map(_hypothesisJson).toList(growable: false),
        ),
        'generated_at': value.generatedAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  ScenarioObservation _observation(Map<String, Object?> row) {
    return ScenarioObservation(
      id: row['id']! as String,
      caseId: row['case_id']! as String,
      evidenceId: row['evidence_id']! as String,
      evidenceSha256: row['evidence_sha256']! as String,
      kind: ScenarioObservationKind.values.byName(row['kind']! as String),
      subjectLabel: row['subject_label']! as String,
      note: row['note']! as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row['created_at']! as int,
        isUtc: true,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row['updated_at']! as int,
        isUtc: true,
      ),
    );
  }

  Map<String, Object?> _hypothesisJson(AccidentScenarioHypothesis value) => {
    'family': value.family.name,
    'title': value.title,
    'possibleSequence': value.possibleSequence,
    'supportingObservationIds': value.supportingObservationIds,
    'supportingEvidenceIds': value.supportingEvidenceIds,
    'contradictions': value.contradictions,
    'missingInformation': value.missingInformation,
    'alternatives': value.alternatives,
    'verificationNeeded': value.verificationNeeded,
  };

  AccidentScenarioHypothesis _hypothesis(Map<String, Object?> value) {
    List<String> strings(String key) => List<String>.from(value[key]! as List);
    return AccidentScenarioHypothesis(
      family: ScenarioFamily.values.byName(value['family']! as String),
      title: value['title']! as String,
      possibleSequence: value['possibleSequence']! as String,
      supportingObservationIds: strings('supportingObservationIds'),
      supportingEvidenceIds: strings('supportingEvidenceIds'),
      contradictions: strings('contradictions'),
      missingInformation: strings('missingInformation'),
      alternatives: strings('alternatives'),
      verificationNeeded: strings('verificationNeeded'),
    );
  }
}
