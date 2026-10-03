import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:pmtiles/pmtiles.dart' as pm;
import 'package:vector_tile/vector_tile.dart' as vt;
import '../domain/case_location.dart';
import '../domain/environment_context.dart';
import '../domain/environment_parser.dart';
import 'bounded_http_client.dart';
import 'environment_provider.dart';

/// Official Overture inspection tiles, z14 full attributes. Footprints are
/// tile-quantized/clipped source geometry, not surveying data. Never whole-world
/// downloads: <=9 tiles, 12 MiB transfer, 2 MiB/tile, 1,000 source buildings.
class OvertureEnvironmentProvider implements EnvironmentProvider {
  OvertureEnvironmentProvider({this.clientFactory});
  final http.Client Function()? clientFactory;
  @override
  String get name => 'Overture Maps';
  static const radius = 150.0;
  @override
  Future<EnvironmentSourceSnapshot> fetch(CaseLocation location) async {
    final client = BoundedHttpClient(inner: clientFactory?.call());
    pm.PmTilesArchive? archive;
    String? release;
    Uri? uri;
    final now = DateTime.now().toUtc();
    try {
      if (!location.latitude.isFinite ||
          !location.longitude.isFinite ||
          location.latitude.abs() > 85 ||
          location.longitude.abs() > 180) {
        throw const FormatException('Location outside supported tile bounds');
      }
      final response = await client.get(
        Uri.parse('https://stac.overturemaps.org/catalog.json'),
      );
      if (response.statusCode != 200) {
        throw http.ClientException('Catalog HTTP ${response.statusCode}');
      }
      final catalog = jsonDecode(response.body) as Map<String, dynamic>;
      release = catalog['latest'] as String?;
      if (release == null ||
          !RegExp(r'^\d{4}-\d{2}-\d{2}\.\d+$').hasMatch(release)) {
        throw const FormatException('Latest Overture release unavailable');
      }
      uri = Uri.https(
        'overturemaps-extras-us-west-2.s3.us-west-2.amazonaws.com',
        '/tiles/$release/buildings.pmtiles',
      );
      archive = await pm.PmTilesArchive.fromUri(uri, client: client);
      const z = 14;
      if (archive.header.maxZoom < z) {
        throw const FormatException('Full building attributes unavailable');
      }
      final deltaLat = radius / 111320;
      final deltaLon =
          radius / (111320 * math.cos(location.latitude * math.pi / 180));
      int tx(double lon) => ((lon + 180) / 360 * (1 << z)).floor();
      int ty(double lat) =>
          ((1 -
                      math.log(
                            math.tan(lat * math.pi / 180) +
                                1 / math.cos(lat * math.pi / 180),
                          ) /
                          math.pi) /
                  2 *
                  (1 << z))
              .floor();
      final minX = tx(location.longitude - deltaLon),
          maxX = tx(location.longitude + deltaLon);
      final minY = ty(location.latitude + deltaLat),
          maxY = ty(location.latitude - deltaLat);
      if ((maxX - minX + 1) * (maxY - minY + 1) > 9 ||
          minX < 0 ||
          maxX >= (1 << z)) {
        throw const FormatException(
          'Bounded tile request unsupported at this location',
        );
      }
      final features = <EnvironmentFeature>[];
      for (var x = minX; x <= maxX; x++) {
        for (var y = minY; y <= maxY; y++) {
          final id = pm.ZXY(z, x, y).toTileId();
          if (await archive.lookup(id) == null) continue;
          final tile = await archive.tile(id);
          final bytes = tile.bytes();
          if (bytes.length > 2 * 1024 * 1024) {
            throw const FormatException('Tile exceeds decode budget');
          }
          features.addAll(
            parseOvertureTile(
              Uint8List.fromList(bytes),
              x,
              y,
              z,
              location,
              release,
            ),
          );
          if (features.length > 2000) {
            throw const FormatException('Building fragment budget exceeded');
          }
        }
      }
      if (features.map((f) => f.sourceId).toSet().length > 1000) {
        throw const FormatException('Building count budget exceeded');
      }
      return EnvironmentSourceSnapshot(
        provider: name,
        state: features.isEmpty
            ? EnvironmentProviderState.successEmpty
            : EnvironmentProviderState.successWithFeatures,
        attemptedAt: now,
        retrievedAt: DateTime.now().toUtc(),
        release: release,
        endpoint: uri.toString(),
        features: features,
        detail: 'z14 clipped/quantized footprints; ${client.transferred} bytes',
      );
    } on FormatException catch (e) {
      return EnvironmentSourceSnapshot(
        provider: name,
        state: EnvironmentProviderState.parseError,
        attemptedAt: now,
        release: release,
        endpoint: uri?.toString(),
        detail: e.message,
      );
    } on Exception {
      return EnvironmentSourceSnapshot(
        provider: name,
        state: EnvironmentProviderState.httpError,
        attemptedAt: now,
        release: release,
        endpoint: uri?.toString(),
        detail: 'Building source request failed',
      );
    } finally {
      await archive?.close();
      client.close();
    }
  }
}

List<EnvironmentFeature> parseOvertureTile(
  Uint8List bytes,
  int x,
  int y,
  int z,
  CaseLocation location,
  String release,
) {
  final tile = vt.VectorTile.fromBytes(bytes: bytes);
  final result = <EnvironmentFeature>[];
  double latitude(double tileY) {
    final n = math.pi * (1 - 2 * tileY / (1 << z));
    return math.atan((math.exp(n) - math.exp(-n)) / 2) * 180 / math.pi;
  }

  final west = x / (1 << z) * 360 - 180, east = (x + 1) / (1 << z) * 360 - 180;
  final north = latitude(y.toDouble()), south = latitude((y + 1).toDouble());
  for (final layer in tile.layers.where((l) => l.name == 'building')) {
    for (final feature in layer.features) {
      if (feature.type != vt.VectorTileGeomType.POLYGON) continue;
      final tags = feature.decodeProperties().map(
        (k, v) => MapEntry(k, '${v.value}'),
      );
      final sourceId = tags['id'];
      if (sourceId == null || sourceId.isEmpty) {
        throw const FormatException('Building stable source ID missing');
      }
      final geo = feature.toGeoJson(x: x, y: y, z: z);
      final polygons = geo is vt.GeoJsonPolygon
          ? [geo.geometry!.coordinates]
          : geo is vt.GeoJsonMultiPolygon
          ? geo.geometry!.coordinates!
          : <List<List<List<double>>>>[];
      var part = 0;
      for (final polygon in polygons) {
        final rings = polygon
            .map((r) => clipRing(r, west, south, east, north))
            .toList();
        if (rings.isEmpty || rings.first.length < 3) continue;
        final outer = rings.first.map((p) => [p[1], p[0]]).toList();
        final local = outer
            .map(
              (p) => localMetricPoint(
                p[0],
                p[1],
                location.latitude,
                location.longitude,
              ),
            )
            .toList();
        // Geographic query bounds are independent of the legacy TASK011 display
        // frame. Retain footprints crossing the +/-150 m query bounding box.
        final deltaLat = OvertureEnvironmentProvider.radius / 111320;
        final deltaLon = deltaLat / math.cos(location.latitude * math.pi / 180);
        final minLat = outer.map((p) => p[0]).reduce(math.min),
            maxLat = outer.map((p) => p[0]).reduce(math.max);
        final minLon = outer.map((p) => p[1]).reduce(math.min),
            maxLon = outer.map((p) => p[1]).reduce(math.max);
        if (minLat > location.latitude + deltaLat ||
            maxLat < location.latitude - deltaLat ||
            minLon > location.longitude + deltaLon ||
            maxLon < location.longitude - deltaLon) {
          continue;
        }
        final holes = rings
            .skip(1)
            .where((r) => r.length >= 3)
            .map((r) => r.map((p) => [p[1], p[0]]).toList())
            .toList();
        result.add(
          EnvironmentFeature(
            id: '$sourceId/$z/$x/$y/${part++}',
            sourceId: sourceId,
            elementType: 'tile_polygon',
            featureType: 'building',
            provider: 'Overture Maps',
            sourceRelease: release,
            coordinates: outer,
            localCoordinates: local,
            holes: holes,
            localHoles: holes
                .map(
                  (r) => r
                      .map(
                        (p) => localMetricPoint(
                          p[0],
                          p[1],
                          location.latitude,
                          location.longitude,
                        ),
                      )
                      .toList(),
                )
                .toList(),
            tags: tags,
          ),
        );
      }
    }
  }
  return result;
}

/// Remove tile buffers to avoid duplicate overlapping fragments at tile seams.
/// Source IDs and tile fragment identity remain separate; no footprints invented.
List<List<double>> clipRing(
  List<List<double>> input,
  double west,
  double south,
  double east,
  double north,
) {
  var ring = input.map((p) => List<double>.of(p)).toList();
  for (final edge in [
    (0, west, true),
    (0, east, false),
    (1, south, true),
    (1, north, false),
  ]) {
    if (ring.isEmpty) break;
    final output = <List<double>>[];
    var a = ring.last;
    bool inside(List<double> p) =>
        edge.$3 ? p[edge.$1] >= edge.$2 : p[edge.$1] <= edge.$2;
    for (final b in ring) {
      if (inside(a) != inside(b)) {
        final t = (edge.$2 - a[edge.$1]) / (b[edge.$1] - a[edge.$1]);
        output.add([a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])]);
      }
      if (inside(b)) output.add(b);
      a = b;
    }
    ring = output;
  }
  if (ring.length > 1 &&
      ring.first[0] == ring.last[0] &&
      ring.first[1] == ring.last[1]) {
    ring.removeLast();
  }
  return ring;
}
