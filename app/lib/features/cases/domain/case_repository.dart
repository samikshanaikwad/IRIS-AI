import 'incident_case.dart';

abstract interface class CaseRepository {
  Future<IncidentCase> createCase({required String title});

  Future<IncidentCase?> getCaseById(String id);

  Future<List<IncidentCase>> getCases({int? limit});

  Future<IncidentCase> renameCase({required String id, required String title});

  Future<bool> deleteCase(String id);
}

class CaseNotFoundException implements Exception {
  const CaseNotFoundException(this.caseId);

  final String caseId;

  @override
  String toString() => 'CaseNotFoundException: $caseId';
}
