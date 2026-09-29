import 'dart:convert';

/// Structured OSM facts. Display meshes are derived later and are not persisted here.
class EnvironmentFeature {
  const EnvironmentFeature({
    required this.id,
    required this.elementType,
    required this.featureType,
    required this.coordinates,
    required this.localCoordinates,
    required this.tags,
  });
  final String id, elementType, featureType;
  final List<List<double>> coordinates, localCoordinates;
  final Map<String, String> tags;
  Map<String, Object?> toJson() => {
    'id': id,
    'elementType': elementType,
    'featureType': featureType,
    'coordinates': coordinates,
    'localCoordinates': localCoordinates,
    'tags': tags,
  };
  factory EnvironmentFeature.fromJson(Map<String, dynamic> json) =>
      EnvironmentFeature(
        id: json['id'] as String,
        elementType: json['elementType'] as String,
        featureType: json['featureType'] as String,
        coordinates: (json['coordinates'] as List)
            .map((p) => (p as List).map((v) => (v as num).toDouble()).toList())
            .toList(),
        localCoordinates: (json['localCoordinates'] as List)
            .map((p) => (p as List).map((v) => (v as num).toDouble()).toList())
            .toList(),
        tags: (json['tags'] as Map).map((k, v) => MapEntry('$k', '$v')),
      );
}

class EnvironmentContext {
  const EnvironmentContext({
    required this.caseId,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.retrievedAt,
    required this.features,
  });
  final String caseId, status;
  final double latitude, longitude;
  final DateTime retrievedAt;
  final List<EnvironmentFeature> features;
  String get provider => 'OpenStreetMap Overpass API';
  String get json => jsonEncode(features.map((f) => f.toJson()).toList());
  int count(String type) => features.where((f) => f.featureType == type).length;
}
