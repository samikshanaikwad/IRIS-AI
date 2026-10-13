import 'dart:convert';
import 'building_appearance.dart';

/// The provider outcome is deliberately separate from supported-feature counts.
/// In particular, a provider or parse failure is not evidence of an empty map.
enum EnvironmentProviderState {
  successWithFeatures,
  successEmpty,
  httpError,
  overpassError,
  parseError,
  noConfirmedLocation,
  offlineUsingPersisted,
  unknown;

  String get storageValue => switch (this) {
    successWithFeatures => 'SUCCESS_WITH_FEATURES',
    successEmpty => 'SUCCESS_EMPTY',
    httpError => 'HTTP_ERROR',
    overpassError => 'OVERPASS_ERROR',
    parseError => 'PARSE_ERROR',
    noConfirmedLocation => 'NO_CONFIRMED_LOCATION',
    offlineUsingPersisted => 'OFFLINE_USING_PERSISTED',
    unknown => 'UNKNOWN',
  };

  bool get isSuccess =>
      this == successWithFeatures ||
      this == successEmpty ||
      this == offlineUsingPersisted;

  static EnvironmentProviderState fromStorage(String? value) =>
      EnvironmentProviderState.values.firstWhere(
        (state) => state.storageValue == value,
        orElse: () => unknown,
      );
}

/// Structured OSM facts. Display meshes are derived later and are not persisted here.
class EnvironmentFeature {
  const EnvironmentFeature({
    required this.id,
    required this.elementType,
    required this.featureType,
    required this.coordinates,
    required this.localCoordinates,
    required this.tags,
    this.provider = 'OpenStreetMap',
    this.sourceRelease,
    this.sourceId,
    this.holes = const [],
    this.localHoles = const [],
  });
  final String id, elementType, featureType;
  final List<List<double>> coordinates, localCoordinates;
  final Map<String, String> tags;
  final String provider;
  final String? sourceRelease, sourceId;
  final List<List<List<double>>> holes, localHoles;
  SurfaceAppearance get wallAppearance =>
      SurfaceAppearance.fromSource(tags['building:colour'], provider);
  SurfaceAppearance get roofAppearance =>
      SurfaceAppearance.fromSource(tags['roof:colour'], provider);
  double? get sourceHeight {
    final value = double.tryParse(
      (tags['height'] ?? '').replaceFirst(RegExp(r'\s*m$'), ''),
    );
    return value != null && value.isFinite && value > 0 ? value : null;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'elementType': elementType,
    'featureType': featureType,
    'coordinates': coordinates,
    'localCoordinates': localCoordinates,
    'tags': tags,
    'provider': provider,
    'sourceRelease': sourceRelease,
    'sourceId': sourceId,
    'holes': holes,
    'localHoles': localHoles,
    // Validated derivatives of original tags; never shaded screen colors.
    // Legacy records remain readable and derive the same appearance on load.
    if (featureType == 'building')
      'appearance': {
        'wall': wallAppearance.toJson(),
        'roof': roofAppearance.toJson(),
      },
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
        provider: json['provider'] as String? ?? 'OpenStreetMap',
        sourceRelease: json['sourceRelease'] as String?,
        sourceId: json['sourceId'] as String?,
        holes: _rings(json['holes']),
        localHoles: _rings(json['localHoles']),
      );
}

List<List<List<double>>> _rings(Object? value) => (value as List? ?? const [])
    .map(
      (ring) => (ring as List)
          .map((p) => (p as List).map((v) => (v as num).toDouble()).toList())
          .toList(),
    )
    .toList();

/// Counts only; a building using neutral on either roof or walls counts once.
Map<String, int> buildingAppearanceCounts(
  Iterable<EnvironmentFeature> features,
) {
  final buildings = features.where((f) => f.featureType == 'building').toList();
  return {
    'buildings': buildings.length,
    'wallColor': buildings.where((f) => f.wallAppearance.argb != null).length,
    'roofColor': buildings.where((f) => f.roofAppearance.argb != null).length,
    'material': buildings
        .where(
          (f) => [
            'building:material',
            'roof:material',
          ].any((k) => f.tags[k]?.trim().isNotEmpty == true),
        )
        .length,
    'height': buildings.where((f) => f.sourceHeight != null).length,
    'unknownNeutral': buildings
        .where(
          (f) => f.wallAppearance.argb == null || f.roofAppearance.argb == null,
        )
        .length,
  };
}

/// The latest request outcome and last usable snapshot are separate. Failed
/// requests never become empty coverage or erase a same-location cache.
class EnvironmentSourceSnapshot {
  const EnvironmentSourceSnapshot({
    required this.provider,
    required this.state,
    required this.attemptedAt,
    this.retrievedAt,
    this.release,
    this.endpoint,
    this.features = const [],
    this.cached = false,
    this.detail,
  });
  final String provider;
  final EnvironmentProviderState state;
  final DateTime attemptedAt;
  final DateTime? retrievedAt;
  final String? release, endpoint, detail;
  final List<EnvironmentFeature> features;
  final bool cached;
  bool get usable => state.isSuccess || (cached && retrievedAt != null);
  EnvironmentSourceSnapshot retaining(EnvironmentSourceSnapshot? old) =>
      state.isSuccess || old == null || !old.usable
      ? this
      : EnvironmentSourceSnapshot(
          provider: provider,
          state: state,
          attemptedAt: attemptedAt,
          retrievedAt: old.retrievedAt,
          release: old.release,
          endpoint: old.endpoint,
          features: old.features,
          cached: true,
          detail: detail,
        );
  Map<String, Object?> toJson() => {
    'provider': provider,
    'state': state.storageValue,
    'attemptedAt': attemptedAt.toIso8601String(),
    'retrievedAt': retrievedAt?.toIso8601String(),
    'release': release,
    'endpoint': endpoint,
    'cached': cached,
    'detail': detail,
    'features': features.map((f) => f.toJson()).toList(),
  };
  factory EnvironmentSourceSnapshot.fromJson(Map<String, dynamic> j) =>
      EnvironmentSourceSnapshot(
        provider: j['provider'] as String,
        state: EnvironmentProviderState.fromStorage(j['state'] as String?),
        attemptedAt: DateTime.parse(j['attemptedAt'] as String),
        retrievedAt: j['retrievedAt'] == null
            ? null
            : DateTime.parse(j['retrievedAt'] as String),
        release: j['release'] as String?,
        endpoint: j['endpoint'] as String?,
        cached: j['cached'] == true,
        detail: j['detail'] as String?,
        features: (j['features'] as List)
            .map(
              (f) => EnvironmentFeature.fromJson(
                Map<String, dynamic>.from(f as Map),
              ),
            )
            .toList(),
      );
}

class EnvironmentContext {
  const EnvironmentContext({
    required this.caseId,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.providerState,
    required this.retrievedAt,
    required this.features,
    this.sources = const [],
  });
  final String caseId, status;
  final EnvironmentProviderState providerState;
  final double latitude, longitude;
  final DateTime retrievedAt;
  final List<EnvironmentFeature> features;
  final List<EnvironmentSourceSnapshot> sources;
  String get provider => sources.isEmpty
      ? 'OpenStreetMap Overpass API'
      : sources.map((s) => s.provider).join(' + ');
  String get json => jsonEncode(features.map((f) => f.toJson()).toList());
  int count(String type) => features
      .where((f) => f.featureType == type)
      .map((f) => '${f.provider}/${f.sourceId ?? f.id}')
      .toSet()
      .length;
  bool get hasVerifiedResult => providerState.isSuccess;
}
