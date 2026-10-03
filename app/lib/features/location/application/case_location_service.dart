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
import '../domain/environment_composition.dart';
import '../data/environment_provider.dart';
import '../data/overture_environment_provider.dart';
import '../data/overpass_environment_provider.dart';

class CaseLocationService {
  CaseLocationService({
    required this.repository,
    required this.storage,
    List<EnvironmentProvider>? environmentProviders,
  }) : environmentProviders =
           environmentProviders ??
           [OvertureEnvironmentProvider(), OverpassEnvironmentProvider()],
       _channel = const MethodChannel('com.iris.location/v1');
  final SqliteCaseLocationRepository repository;
  final EvidenceStorage storage;
  final List<EnvironmentProvider> environmentProviders;
  final Map<String, Future<EnvironmentContext?>> _refreshes = {};
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
  Future<RoadContext?> loadRoadContext(String caseId) async {
    final location = await load(caseId);
    final roads = await repository.getRoadContext(caseId);
    return location != null &&
            roads != null &&
            sameEnvironmentLocation(roads.latitude, roads.longitude, location)
        ? roads
        : null;
  }

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
      if (response.statusCode != 200) {
        return RoadContext(
          caseId: location.caseId,
          latitude: location.latitude,
          longitude: location.longitude,
          status: 'UNAVAILABLE',
          retrievedAt: DateTime.now(),
          roads: const [],
        );
      }
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

  Future<void> saveRoadContext(RoadContext context) async {
    final current = await load(context.caseId);
    if (current == null ||
        !sameEnvironmentLocation(
          context.latitude,
          context.longitude,
          current,
        )) {
      return;
    }
    final cached = await loadRoadContext(context.caseId);
    if (context.status != 'AVAILABLE' && cached?.status == 'AVAILABLE') return;
    await repository.saveRoadContext(context);
  }

  Future<EnvironmentContext?> loadEnvironment(String caseId) async {
    final location = await load(caseId);
    if (location == null) return null;
    final context = await repository.getEnvironmentContext(caseId);
    if (context == null) return null;
    return sameEnvironmentLocation(
          context.latitude,
          context.longitude,
          location,
        )
        ? context
        : null;
  }

  static String environmentQuery(CaseLocation location) =>
      OverpassEnvironmentProvider.query(location);

  Future<EnvironmentContext?> fetchEnvironmentForCase(String caseId) async {
    final location = await load(caseId);
    if (location == null) return null;
    final cached = await loadEnvironment(caseId);
    final attempts = await Future.wait(
      environmentProviders.map((provider) async {
        EnvironmentSourceSnapshot result;
        try {
          result = await provider.fetch(location);
        } on Object {
          // Isolate malformed/failed sources; a decoder failure must not erase
          // another provider's valid data or masquerade as empty coverage.
          result = EnvironmentSourceSnapshot(
            provider: provider.name,
            state: EnvironmentProviderState.parseError,
            attemptedAt: DateTime.now().toUtc(),
            detail: 'Provider could not produce a valid source snapshot',
          );
        }
        await _diagnostic(
          'source=${result.provider} state=${result.state.storageValue} '
          'buildings=${result.features.where((f) => f.featureType == 'building').map((f) => f.sourceId ?? f.id).toSet().length} '
          'sourceHeightBuildings=${result.features.where((f) => f.featureType == 'building' && f.sourceHeight != null).map((f) => f.sourceId ?? f.id).toSet().length} '
          'trees=${result.features.where((f) => f.featureType == 'tree').length} '
          'barriers=${result.features.where((f) => f.featureType == 'barrier').length}',
        );
        return result;
      }),
    );
    return composeEnvironment(location, attempts, cached);
  }

  Future<EnvironmentContext?> refreshEnvironment(String caseId) =>
      _refreshes.putIfAbsent(
        caseId,
        () => _refresh(caseId).whenComplete(() {
          _refreshes.remove(caseId);
        }),
      );

  Future<EnvironmentContext?> _refresh(String caseId) async {
    final result = await fetchEnvironmentForCase(caseId);
    if (result == null) return null;
    // The transactional save checks location again: navigation/location edits
    // while HTTP is in flight cannot attach old geometry to a different world.
    if (!await repository.saveApplicableEnvironment(result)) return null;
    final reloaded = await loadEnvironment(caseId);
    await _diagnostic(
      'stage=reloaded buildings=${reloaded?.count('building')} '
      'trees=${reloaded?.count('tree')} barriers=${reloaded?.count('barrier')}',
    );
    return reloaded;
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
    return localMetricPoint(lat, lon, originLat, originLon);
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
