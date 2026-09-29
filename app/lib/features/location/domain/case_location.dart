enum CaseLocationSource { evidenceExif, mapSelection, searchResult, deviceCurrentLocation }

extension CaseLocationSourceText on CaseLocationSource {
  String get storageValue => switch (this) {
    CaseLocationSource.evidenceExif => 'EVIDENCE_EXIF',
    CaseLocationSource.mapSelection => 'MAP_SELECTION',
    CaseLocationSource.searchResult => 'SEARCH_RESULT',
    CaseLocationSource.deviceCurrentLocation => 'DEVICE_CURRENT_LOCATION',
  };
  String get label => switch (this) {
    CaseLocationSource.evidenceExif => 'Evidence GPS',
    CaseLocationSource.mapSelection => 'Map selection',
    CaseLocationSource.searchResult => 'Search result',
    CaseLocationSource.deviceCurrentLocation => 'Current device location',
  };
}

class CaseLocation {
  const CaseLocation({required this.caseId, required this.latitude, required this.longitude, required this.source, this.sourceEvidenceId, this.placeLabel, required this.updatedAt});
  final String caseId;
  final double latitude, longitude;
  final CaseLocationSource source;
  final String? sourceEvidenceId, placeLabel;
  final DateTime updatedAt;
}
