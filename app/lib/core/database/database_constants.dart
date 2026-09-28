abstract final class IrisDatabaseConstants {
  static const String fileName = 'iris.db';
  static const int schemaVersion = 4;

  static const String casesTable = 'cases';
  static const String casesUpdatedAtIndex = 'idx_cases_updated_at';
  static const String evidenceTable = 'evidence_images';
  static const String evidenceCaseIndex = 'idx_evidence_case_imported';
  static const String evidenceQualityTable = 'evidence_quality_assessments';
  static const String evidenceClassificationTable = 'evidence_classifications';
}
