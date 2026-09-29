abstract final class IrisDatabaseConstants {
  static const String fileName = 'iris.db';
  static const int schemaVersion = 12;

  static const String casesTable = 'cases';
  static const String casesUpdatedAtIndex = 'idx_cases_updated_at';
  static const String evidenceTable = 'evidence_images';
  static const String evidenceCaseIndex = 'idx_evidence_case_imported';
  static const String evidenceQualityTable = 'evidence_quality_assessments';
  static const String evidenceClassificationTable = 'evidence_classifications';
  static const String evidenceDetectionAnalysesTable =
      'evidence_detection_analyses';
  static const String evidenceDetectionsTable = 'evidence_detections';
  static const String evidenceDepthAnalysesTable = 'evidence_depth_analyses';
  static const String evidenceGeometryAnalysesTable =
      'evidence_geometry_analyses';
  static const String multiViewPairAnalysesTable = 'multiview_pair_analyses';
  static const String caseLocationsTable = 'case_locations';
  static const String roadContextsTable = 'road_contexts';
  static const String evidenceWorldAlignmentsTable =
      'evidence_world_alignments';
  static const String environmentContextsTable = 'environment_contexts';
}
