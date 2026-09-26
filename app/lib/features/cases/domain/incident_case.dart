import 'case_status.dart';

class IncidentCase {
  const IncidentCase({
    required this.id,
    required this.title,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.incidentOccurredAt,
    this.notes,
  });

  final String id;
  final String title;
  final CaseStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? incidentOccurredAt;
  final String? notes;
}
