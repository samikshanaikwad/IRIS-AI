import 'case_location.dart';
import 'environment_context.dart';

bool sameEnvironmentLocation(
  double latitude,
  double longitude,
  CaseLocation location,
) => latitude == location.latitude && longitude == location.longitude;

EnvironmentContext composeEnvironment(
  CaseLocation location,
  List<EnvironmentSourceSnapshot> attempts,
  EnvironmentContext? cached,
) {
  final old =
      cached != null &&
          sameEnvironmentLocation(cached.latitude, cached.longitude, location)
      ? cached
      : null;
  final previous = <String, EnvironmentSourceSnapshot>{
    for (final s in old?.sources ?? <EnvironmentSourceSnapshot>[])
      s.provider: s,
  };
  if (previous.isEmpty && old?.hasVerifiedResult == true) {
    previous['OpenStreetMap'] = EnvironmentSourceSnapshot(
      provider: 'OpenStreetMap',
      state: old!.providerState,
      attemptedAt: old.retrievedAt,
      retrievedAt: old.retrievedAt,
      features: old.features,
    );
  }
  final sources = attempts
      .map((s) => s.retaining(previous[s.provider]))
      .toList();
  // Source precedence, not guessed entity identity: a usable Overture building
  // layer with footprints owns building coverage in this bounded area. OSM
  // supplies trees/barriers and buildings when Overture has no usable footprints.
  final overtureAvailable = sources.any(
    (s) =>
        s.provider == 'Overture Maps' &&
        s.usable &&
        s.features.any((f) => f.featureType == 'building'),
  );
  final features = sources
      .where((s) => s.usable)
      .expand(
        (s) => s.features.where(
          (f) =>
              f.featureType != 'building' ||
              !overtureAvailable ||
              s.provider == 'Overture Maps',
        ),
      )
      .toList();
  final usable = sources.any((s) => s.usable);
  return EnvironmentContext(
    caseId: location.caseId,
    latitude: location.latitude,
    longitude: location.longitude,
    status: usable ? (features.isEmpty ? 'EMPTY' : 'AVAILABLE') : 'UNAVAILABLE',
    providerState: usable
        ? (sources.any((s) => s.cached)
              ? EnvironmentProviderState.offlineUsingPersisted
              : features.isEmpty
              ? EnvironmentProviderState.successEmpty
              : EnvironmentProviderState.successWithFeatures)
        : attempts.isEmpty
        ? EnvironmentProviderState.unknown
        : attempts.first.state,
    retrievedAt: DateTime.now().toUtc(),
    features: features,
    sources: sources,
  );
}
