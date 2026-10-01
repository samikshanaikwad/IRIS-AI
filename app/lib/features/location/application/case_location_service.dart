import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../evidence/data/evidence_storage.dart';
import '../../evidence/domain/evidence_image.dart';
import '../data/sqlite_case_location_repository.dart';
import '../domain/case_location.dart';
import '../domain/road_context.dart';
import '../domain/environment_context.dart';
import '../domain/environment_parser.dart';

class CaseLocationService {
  CaseLocationService({required this.repository, required this.storage})
    : _channel = const MethodChannel('com.iris.location/v1');
  final SqliteCaseLocationRepository repository;
  final EvidenceStorage storage;
  final MethodChannel _channel;
  static const MethodChannel _environmentDiagnosticChannel = MethodChannel(
    'com.iris.debug/environment',
  );
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
    final query = environmentQuery(location);
    try {
      final response = await http
          .get(
            Uri.https('overpass-api.de', '/api/interpreter', {'data': query}),
            headers: {'User-Agent': 'IRIS-V0-local-development'},
          )
          .timeout(const Duration(seconds: 20));
      developer.log(
        'httpStatus=${response.statusCode} responseBytes=${response.bodyBytes.length}',
        name: 'IRIS.environment',
      );
      await _diagnostic(
        'httpStatus=${response.statusCode} responseBytes=${response.bodyBytes.length}',
      );
      if (response.statusCode != 200) {
        await _diagnostic('providerState=HTTP_ERROR');
        return _environmentFailure(
          caseId,
          location,
          EnvironmentProviderState.httpError,
        );
      }
      final Object? decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        await _diagnostic(
          'providerState=${_overpassOrParseState(response.body).storageValue}',
        );
        return _environmentFailure(
          caseId,
          location,
          _overpassOrParseState(response.body),
        );
      }
      if (decoded is! Map) {
        await _diagnostic('providerState=PARSE_ERROR');
        return _environmentFailure(
          caseId,
          location,
          EnvironmentProviderState.parseError,
        );
      }
      final payload = Map<String, dynamic>.from(decoded);
      if (payload['remark'] != null || payload['error'] != null) {
        await _diagnostic('providerState=OVERPASS_ERROR');
        return _environmentFailure(
          caseId,
          location,
          EnvironmentProviderState.overpassError,
        );
      }
      final elements = payload['elements'];
      if (elements is! List) {
        await _diagnostic('providerState=PARSE_ERROR');
        return _environmentFailure(
          caseId,
          location,
          EnvironmentProviderState.parseError,
        );
      }
      final parsed = parseEnvironmentElements(
        elements: elements,
        originLatitude: location.latitude,
        originLongitude: location.longitude,
      );
      developer.log(parsed.diagnostics.logLine, name: 'IRIS.environment');
      await _diagnostic(parsed.diagnostics.logLine);
      final providerState = parsed.features.isEmpty
          ? EnvironmentProviderState.successEmpty
          : EnvironmentProviderState.successWithFeatures;
      return EnvironmentContext(
        caseId: caseId,
        latitude: location.latitude,
        longitude: location.longitude,
        status: parsed.features.isEmpty ? 'EMPTY' : 'AVAILABLE',
        providerState: providerState,
        retrievedAt: DateTime.now(),
        features: parsed.features,
      );
    } catch (_) {
      developer.log(
        'providerState=HTTP_OR_NETWORK_ERROR',
        name: 'IRIS.environment',
      );
      await _diagnostic('providerState=HTTP_OR_NETWORK_ERROR');
      return _environmentFailure(
        caseId,
        location,
        EnvironmentProviderState.httpError,
      );
    }
  }

  /// Bounded, geometry-bearing query contract for the current confirmed case
  /// location. The query is never built from device-current location.
  static String environmentQuery(CaseLocation location) =>
      '[out:json][timeout:15];('
      'way(around:150,${location.latitude},${location.longitude})["building"];'
      'relation(around:150,${location.latitude},${location.longitude})["building"];'
      'node(around:150,${location.latitude},${location.longitude})["natural"="tree"];'
      'way(around:150,${location.latitude},${location.longitude})["barrier"~"^(wall|fence|guard_rail)\$"];'
      ');out tags geom;';

  Future<EnvironmentContext?> refreshEnvironment(String caseId) async {
    final result = await fetchEnvironmentForCase(caseId);
    if (result != null) {
      // A failed refresh must not erase a valid environment already stored for
      // this same confirmed location.
      if (result.providerState.isSuccess) {
        await repository.saveEnvironmentContext(result);
      }
      final reloaded = await loadEnvironment(caseId);
      developer.log(
        'providerState=${result.providerState.storageValue} '
        'persistedBuildings=${reloaded?.count('building') ?? 0} '
        'persistedTrees=${reloaded?.count('tree') ?? 0} '
        'persistedBarriers=${reloaded?.count('barrier') ?? 0} '
        'reloadedBuildings=${reloaded?.count('building') ?? 0} '
        'reloadedTrees=${reloaded?.count('tree') ?? 0} '
        'reloadedBarriers=${reloaded?.count('barrier') ?? 0}',
        name: 'IRIS.environment',
      );
      await _diagnostic(
        'providerState=${result.providerState.storageValue} '
        'persistedBuildings=${reloaded?.count('building') ?? 0} '
        'persistedTrees=${reloaded?.count('tree') ?? 0} '
        'persistedBarriers=${reloaded?.count('barrier') ?? 0} '
        'reloadedBuildings=${reloaded?.count('building') ?? 0} '
        'reloadedTrees=${reloaded?.count('tree') ?? 0} '
        'reloadedBarriers=${reloaded?.count('barrier') ?? 0}',
      );
    }
    return result;
  }

  EnvironmentContext _environmentFailure(
    String caseId,
    CaseLocation location,
    EnvironmentProviderState providerState,
  ) => EnvironmentContext(
    caseId: caseId,
    latitude: location.latitude,
    longitude: location.longitude,
    status: 'UNAVAILABLE',
    providerState: providerState,
    retrievedAt: DateTime.now(),
    features: const [],
  );

  EnvironmentProviderState _overpassOrParseState(String body) {
    final normalized = body.toLowerCase();
    final isOverpassError =
        normalized.contains('osm3s') ||
        normalized.contains('overpass') ||
        normalized.contains('runtime error') ||
        normalized.contains('dispatcher');
    return isOverpassError
        ? EnvironmentProviderState.overpassError
        : EnvironmentProviderState.parseError;
  }

  Future<void> _diagnostic(String message) async {
    if (!kDebugMode) return;
    try {
      await _environmentDiagnosticChannel.invokeMethod<void>('logCounts', {
        'message': message,
      });
    } on MissingPluginException {
      // Unit tests and non-Android targets intentionally have no debug bridge.
    } on PlatformException {
      // Diagnostics must never change production environment retrieval.
    }
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
