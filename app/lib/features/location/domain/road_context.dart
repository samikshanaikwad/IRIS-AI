import 'dart:convert';

class RoadSegment {
  const RoadSegment({required this.id, this.name, this.roadClass, this.lanes, this.width, required this.coordinates, required this.localCoordinates});
  final String id; final String? name, roadClass; final int? lanes; final double? width;
  final List<List<double>> coordinates, localCoordinates;
  Map<String, Object?> toJson() => {'id': id, 'name': name, 'roadClass': roadClass, 'lanes': lanes, 'width': width, 'coordinates': coordinates, 'localCoordinates': localCoordinates};
  factory RoadSegment.fromJson(Map<String, dynamic> json) => RoadSegment(id: json['id'] as String, name: json['name'] as String?, roadClass: json['roadClass'] as String?, lanes: json['lanes'] as int?, width: (json['width'] as num?)?.toDouble(), coordinates: (json['coordinates'] as List).map((p) => (p as List).map((v) => (v as num).toDouble()).toList()).toList(), localCoordinates: (json['localCoordinates'] as List).map((p) => (p as List).map((v) => (v as num).toDouble()).toList()).toList());
}
class RoadContext { const RoadContext({required this.caseId, required this.latitude, required this.longitude, required this.status, required this.retrievedAt, required this.roads}); final String caseId; final double latitude, longitude; final String status; final DateTime retrievedAt; final List<RoadSegment> roads; String get provider => 'OpenStreetMap Overpass API'; String get json => jsonEncode(roads.map((r) => r.toJson()).toList()); }
