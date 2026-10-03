import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/case_location.dart';
import '../domain/environment_context.dart';
import '../domain/environment_parser.dart';
import 'bounded_http_client.dart';
import 'environment_provider.dart';

class OverpassEnvironmentProvider implements EnvironmentProvider {
  OverpassEnvironmentProvider({
    this.clientFactory,
    this.delay = const Duration(seconds: 1),
  });
  final http.Client Function()? clientFactory;
  final Duration delay;
  @override
  String get name => 'OpenStreetMap';
  // Both are documented public instances. Two attempts total, not an indefinite
  // retry loop. Review public service capacity before production-scale rollout.
  static const endpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
  ];
  static String query(CaseLocation p) =>
      '[out:json][timeout:15];('
      'way(around:150,${p.latitude},${p.longitude})["building"];'
      'relation(around:150,${p.latitude},${p.longitude})["building"];'
      'node(around:150,${p.latitude},${p.longitude})["natural"="tree"];'
      'way(around:150,${p.latitude},${p.longitude})["barrier"~"^(wall|fence|guard_rail)\$"];'
      ');out tags geom;';
  @override
  Future<EnvironmentSourceSnapshot> fetch(CaseLocation location) async {
    var state = EnvironmentProviderState.httpError;
    String? detail;
    for (var i = 0; i < endpoints.length; i++) {
      if (i > 0) await Future<void>.delayed(delay);
      final client = BoundedHttpClient(
        inner: clientFactory?.call(),
        maxBytes: 4 * 1024 * 1024,
      );
      try {
        final response = await client.post(
          Uri.parse(endpoints[i]),
          body: {'data': query(location)},
        );
        if (response.statusCode != 200) {
          state = EnvironmentProviderState.httpError;
          detail = 'HTTP ${response.statusCode}';
          continue;
        }
        final raw = jsonDecode(response.body);
        if (raw is Map && (raw['remark'] != null || raw['error'] != null)) {
          state = EnvironmentProviderState.overpassError;
          detail = 'Overpass returned an error';
          continue;
        }
        if (raw is! Map || raw['elements'] is! List) {
          state = EnvironmentProviderState.parseError;
          detail = 'Missing elements array';
          continue;
        }
        final parsed = parseEnvironmentElements(
          elements: raw['elements'] as List,
          originLatitude: location.latitude,
          originLongitude: location.longitude,
        );
        final now = DateTime.now().toUtc();
        return EnvironmentSourceSnapshot(
          provider: name,
          state: parsed.features.isEmpty
              ? EnvironmentProviderState.successEmpty
              : EnvironmentProviderState.successWithFeatures,
          attemptedAt: now,
          retrievedAt: now,
          endpoint: endpoints[i],
          features: parsed.features,
          detail: parsed.diagnostics.logLine,
        );
      } on FormatException {
        state = EnvironmentProviderState.parseError;
        detail = 'Invalid provider JSON';
      } on Exception {
        state = EnvironmentProviderState.httpError;
        detail = 'Request unavailable or timed out';
      } finally {
        client.close();
      }
    }
    return EnvironmentSourceSnapshot(
      provider: name,
      state: state,
      attemptedAt: DateTime.now().toUtc(),
      endpoint: endpoints.last,
      detail: detail,
    );
  }
}
