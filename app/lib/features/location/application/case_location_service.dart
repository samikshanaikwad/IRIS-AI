import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../evidence/data/evidence_storage.dart';
import '../../evidence/domain/evidence_image.dart';
import '../data/sqlite_case_location_repository.dart';
import '../domain/case_location.dart';
import '../domain/road_context.dart';
import '../domain/environment_context.dart';

class CaseLocationService {
  CaseLocationService({required this.repository, required this.storage})
    : _channel = const MethodChannel('com.iris.location/v1');
  final SqliteCaseLocationRepository repository;
  final EvidenceStorage storage;
  final MethodChannel _channel;
  Future<CaseLocation?> current(String caseId) async {
    final raw = Map<String, dynamic>.from(
      await _channel.invokeMethod<Map<Object?, Object?>>('currentLocation') ??
          {},
    );
    if (raw['status'] != 'AVAILABLE') return null;
    return _candidate(
      caseId,
      (raw['latitude'] as num).toDouble(),
      (raw['longitude'] as num).toDouble(),
      CaseLocationSource.deviceCurrentLocation,
    );
  }

  Future<CaseLocation?> evidenceGps(
    String caseId,
    EvidenceImage evidence,
  ) async {
    final raw = Map<String, dynamic>.from(
      await _channel.invokeMethod<Map<Object?, Object?>>('readGps', {
            'path': await storage.absolutePath(evidence.storedRelativePath),
          }) ??
          {},
    );
    if (raw['status'] != 'AVAILABLE') return null;
    return _candidate(
      caseId,
      (raw['latitude'] as num).toDouble(),
      (raw['longitude'] as num).toDouble(),
      CaseLocationSource.evidenceExif,
      sourceEvidenceId: evidence.id,
    );
  }

  Future<void> confirm(CaseLocation value) => repository.save(value);
  Future<CaseLocation?> load(String caseId) => repository.get(caseId);
  Future<RoadContext?> loadRoadContext(String caseId) =>
      repository.getRoadContext(caseId);
  Future<RoadContext> fetchRoadContext(CaseLocation location) async {
    final query =
        '[out:json][timeout:10];way(around:250,${location.latitude},${location.longitude})[highway];out tags geom;';
    try {
      final response = await http
          .get(
            Uri.https('overpass-api.de', '/api/interpreter', {'data': query}),
            headers: {'User-Agent': 'IRIS-V0-local-development'},
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200)
        return RoadContext(
          caseId: location.caseId,
          latitude: location.latitude,
          longitude: location.longitude,
          status: 'UNAVAILABLE',
          retrievedAt: DateTime.now(),
          roads: const [],
        );
      final elements =
          (jsonDecode(response.body)['elements'] as List?) ?? const [];
      final roads = <RoadSegment>[];
      for (final element in elements) {
        final item = element as Map<String, dynamic>;
        final geometry = (item['geometry'] as List?) ?? const [];
        final points = geometry
            .map(
              (p) => <double>[
                (p['lat'] as num).toDouble(),
                (p['lon'] as num).toDouble(),
              ],
            )
            .toList();
        if (points.isEmpty) continue;
        final tags = (item['tags'] as Map?)?.cast<String, dynamic>() ?? {};
        roads.add(
          RoadSegment(
            id: '${item['id']}',
            name: tags['name'] as String?,
            roadClass: tags['highway'] as String?,
            lanes: int.tryParse('${tags['lanes'] ?? ''}'),
            width: double.tryParse('${tags['width'] ?? ''}'),
            coordinates: points,
            localCoordinates: points
                .map(
                  (p) =>
                      _local(p[0], p[1], location.latitude, location.longitude),
                )
                .toList(),
          ),
        );
      }
      return RoadContext(
        caseId: location.caseId,
        latitude: location.latitude,
        longitude: location.longitude,
        status: roads.isEmpty ? 'UNAVAILABLE' : 'AVAILABLE',
        retrievedAt: DateTime.now(),
        roads: roads,
      );
    } catch (_) {
      return RoadContext(
        caseId: location.caseId,
        latitude: location.latitude,
        longitude: location.longitude,
        status: 'UNAVAILABLE',
        retrievedAt: DateTime.now(),
        roads: const [],
      );
    }
  }

  Future<void> saveRoadContext(RoadContext context) =>
      repository.saveRoadContext(context);
  Future<EnvironmentContext?> loadEnvironment(String caseId) async {
    final location = await load(caseId);
    if (location == null) return null;
    final context = await repository.getEnvironmentContext(caseId);
    if (context == null) return null;
    const tolerance = 0.000001;
    return (context.latitude - location.latitude).abs() <= tolerance &&
            (context.longitude - location.longitude).abs() <= tolerance
        ? context
        : null;
  }

  Future<EnvironmentContext?> fetchEnvironmentForCase(String caseId) async {
    final location = await load(caseId);
    if (location == null) return null;
    final query =
        '[out:json][timeout:15];(way(around:150,${location.latitude},${location.longitude})["building"];relation(around:150,${location.latitude},${location.longitude})["building"];node(around:150,${location.latitude},${location.longitude})["natural"="tree"];way(around:150,${location.latitude},${location.longitude})["barrier"~"^(wall|fence|guard_rail)\$"];);out tags geom;';
    try {
      final response = await http
          .get(
            Uri.https('overpass-api.de', '/api/interpreter', {'data': query}),
            headers: {'User-Agent': 'IRIS-V0-local-development'},
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200)
        return EnvironmentContext(
          caseId: caseId,
          latitude: location.latitude,
          longitude: location.longitude,
          status: 'UNAVAILABLE',
          retrievedAt: DateTime.now(),
          features: const [],
        );
      final elements =
          (jsonDecode(response.body)['elements'] as List?) ?? const [];
      final features = <EnvironmentFeature>[];
      for (final raw in elements) {
        final item = raw as Map<String, dynamic>;
        final tags = ((item['tags'] as Map?) ?? const {}).map(
          (k, v) => MapEntry('$k', '$v'),
        );
        final kind = tags.containsKey('building')
            ? 'building'
            : tags['natural'] == 'tree'
            ? 'tree'
            : tags.containsKey('barrier')
            ? 'barrier'
            : null;
        if (kind == null) continue;
        final geometry = (item['geometry'] as List?) ?? const [];
        final points = geometry
            .map(
              (p) => <double>[
                (p['lat'] as num).toDouble(),
                (p['lon'] as num).toDouble(),
              ],
            )
            .toList();
        if (points.isEmpty && item['lat'] != null && item['lon'] != null)
          points.add([
            (item['lat'] as num).toDouble(),
            (item['lon'] as num).toDouble(),
          ]);
        if (points.isEmpty) continue;
        features.add(
          EnvironmentFeature(
            id: '${item['type']}/${item['id']}',
            elementType: item['type'] as String,
            featureType: kind,
            coordinates: points,
            localCoordinates: points
                .map(
                  (p) =>
                      _local(p[0], p[1], location.latitude, location.longitude),
                )
                .toList(),
            tags: tags,
          ),
        );
      }
      return EnvironmentContext(
        caseId: caseId,
        latitude: location.latitude,
        longitude: location.longitude,
        status: features.isEmpty ? 'EMPTY' : 'AVAILABLE',
        retrievedAt: DateTime.now(),
        features: features,
      );
    } catch (_) {
      return EnvironmentContext(
        caseId: caseId,
        latitude: location.latitude,
        longitude: location.longitude,
        status: 'UNAVAILABLE',
        retrievedAt: DateTime.now(),
        features: const [],
      );
    }
  }

  Future<EnvironmentContext?> refreshEnvironment(String caseId) async {
    final result = await fetchEnvironmentForCase(caseId);
    if (result != null) await repository.saveEnvironmentContext(result);
    return result;
  }

  List<double> _local(
    double lat,
    double lon,
    double originLat,
    double originLon,
  ) {
    const metersPerDegree = 111320.0;
    final x = (lon - originLon) * metersPerDegree * 0.999;
    final z = (lat - originLat) * metersPerDegree;
    return [x, z];
  }

  CaseLocation _candidate(
    String caseId,
    double latitude,
    double longitude,
    CaseLocationSource source, {
    String? sourceEvidenceId,
  }) => CaseLocation(
    caseId: caseId,
    latitude: latitude,
    longitude: longitude,
    source: source,
    sourceEvidenceId: sourceEvidenceId,
    updatedAt: DateTime.now(),
  );
}
