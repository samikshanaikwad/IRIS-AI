import 'accident_scenario.dart';

abstract interface class AccidentScenarioRepository {
  Future<List<ScenarioObservation>> observations(String caseId);
  Future<void> saveObservation(ScenarioObservation value);
  Future<void> deleteObservation(String id);
  Future<AccidentScenarioAnalysis?> analysis(String caseId);
  Future<void> saveAnalysis(AccidentScenarioAnalysis value);
}
