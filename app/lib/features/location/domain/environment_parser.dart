import 'environment_context.dart';

/// Counts retained for development diagnostics. They contain no case location
/// or evidence information and never become incident-environment facts.
class EnvironmentDiagnostics {
  const EnvironmentDiagnostics({
    required this.totalElements,
    required this.nodes,
    required this.ways,
    required this.relations,
    required this.taggedBuildingWays,
    required this.taggedBuildingRelations,
    required this.taggedTrees,
    required this.taggedBarriers,
    required this.usableBuildings,
    required this.usableTrees,
    required this.usableBarriers,
    required this.parsedBuildings,
    required this.parsedTrees,
    required this.parsedBarriers,
    required this.unsupportedBuildingRelations,
  });

  const EnvironmentDiagnostics.empty()
    : totalElements = 0,
      nodes = 0,
      ways = 0,
      relations = 0,
      taggedBuildingWays = 0,
      taggedBuildingRelations = 0,
      taggedTrees = 0,
      taggedBarriers = 0,
      usableBuildings = 0,
      usableTrees = 0,
      usableBarriers = 0,
      parsedBuildings = 0,
      parsedTrees = 0,
      parsedBarriers = 0,
      unsupportedBuildingRelations = 0;

  final int totalElements, nodes, ways, relations;
  final int taggedBuildingWays,
      taggedBuildingRelations,
      taggedTrees,
      taggedBarriers;
  final int usableBuildings, usableTrees, usableBarriers;
  final int parsedBuildings, parsedTrees, parsedBarriers;
  final int unsupportedBuildingRelations;

  String get logLine =>
      'elements=$totalElements nodes=$nodes ways=$ways relations=$relations '
      'taggedBuildingWays=$taggedBuildingWays '
      'taggedBuildingRelations=$taggedBuildingRelations '
      'taggedTrees=$taggedTrees taggedBarriers=$taggedBarriers '
      'usableBuildings=$usableBuildings usableTrees=$usableTrees '
      'usableBarriers=$usableBarriers parsedBuildings=$parsedBuildings '
      'parsedTrees=$parsedTrees parsedBarriers=$parsedBarriers '
      'unsupportedBuildingRelations=$unsupportedBuildingRelations';
}

class ParsedEnvironment {
  const ParsedEnvironment({required this.features, required this.diagnostics});
  final List<EnvironmentFeature> features;
  final EnvironmentDiagnostics diagnostics;
}

/// Parses only the OSM feature types supported by TASK012F. It intentionally
/// does not invent geometry for incomplete ways or relations.
ParsedEnvironment parseEnvironmentElements({
  required List<dynamic> elements,
  required double originLatitude,
  required double originLongitude,
}) {
  var nodes = 0, ways = 0, relations = 0;
  var taggedBuildingWays = 0, taggedBuildingRelations = 0;
  var taggedTrees = 0, taggedBarriers = 0;
  var usableBuildings = 0, usableTrees = 0, usableBarriers = 0;
  var parsedBuildings = 0, parsedTrees = 0, parsedBarriers = 0;
  var unsupportedBuildingRelations = 0;
  final features = <EnvironmentFeature>[];

  for (final raw in elements) {
    if (raw is! Map) continue;
    final item = raw.map((key, value) => MapEntry('$key', value));
    final type = item['type'] as String?;
    switch (type) {
      case 'node':
        nodes++;
      case 'way':
        ways++;
      case 'relation':
        relations++;
      default:
        continue;
    }
    final tags = _tags(item['tags']);
    final isBuilding = tags.containsKey('building') && tags['building'] != 'no';
    final isTree = type == 'node' && tags['natural'] == 'tree';
    final isBarrier =
        type == 'way' &&
        const {'wall', 'fence', 'guard_rail'}.contains(tags['barrier']);
    if (isBuilding && type == 'way') taggedBuildingWays++;
    if (isBuilding && type == 'relation') taggedBuildingRelations++;
    if (isTree) taggedTrees++;
    if (isBarrier) taggedBarriers++;

    List<List<double>>? coordinates;
    String? featureType;
    if (isBuilding) {
      coordinates = _closedFootprint(_geometry(item['geometry']));
      if (coordinates == null && type == 'relation') {
        coordinates = _relationOuterFootprint(item['members']);
      }
      if (coordinates == null) {
        if (type == 'relation') unsupportedBuildingRelations++;
        continue;
      }
      usableBuildings++;
      featureType = 'building';
      parsedBuildings++;
    } else if (isTree) {
      coordinates = _nodePoint(item);
      if (coordinates == null) continue;
      usableTrees++;
      featureType = 'tree';
      parsedTrees++;
    } else if (isBarrier) {
      coordinates = _path(_geometry(item['geometry']));
      if (coordinates == null) continue;
      usableBarriers++;
      featureType = 'barrier';
      parsedBarriers++;
    } else {
      continue;
    }
    final id = item['id'];
    if (id == null) continue;
    features.add(
      EnvironmentFeature(
        id: '$type/$id',
        elementType: type!,
        featureType: featureType,
        coordinates: coordinates,
        localCoordinates: coordinates
            .map(
              (point) => localMetricPoint(
                point[0],
                point[1],
                originLatitude,
                originLongitude,
              ),
            )
            .toList(),
        tags: tags,
      ),
    );
  }
  return ParsedEnvironment(
    features: List.unmodifiable(features),
    diagnostics: EnvironmentDiagnostics(
      totalElements: elements.length,
      nodes: nodes,
      ways: ways,
      relations: relations,
      taggedBuildingWays: taggedBuildingWays,
      taggedBuildingRelations: taggedBuildingRelations,
      taggedTrees: taggedTrees,
      taggedBarriers: taggedBarriers,
      usableBuildings: usableBuildings,
      usableTrees: usableTrees,
      usableBarriers: usableBarriers,
      parsedBuildings: parsedBuildings,
      parsedTrees: parsedTrees,
      parsedBarriers: parsedBarriers,
      unsupportedBuildingRelations: unsupportedBuildingRelations,
    ),
  );
}

List<double> localMetricPoint(
  double latitude,
  double longitude,
  double originLatitude,
  double originLongitude,
) {
  const metresPerDegree = 111320.0;
  return [
    (longitude - originLongitude) * metresPerDegree * .999,
    (latitude - originLatitude) * metresPerDegree,
  ];
}

Map<String, String> _tags(Object? raw) =>
    raw is Map ? raw.map((key, value) => MapEntry('$key', '$value')) : const {};

List<List<double>> _geometry(Object? raw) {
  if (raw is! List) return const [];
  final points = <List<double>>[];
  for (final value in raw) {
    if (value is! Map) return const [];
    final lat = value['lat'];
    final lon = value['lon'];
    if (lat is! num || lon is! num) return const [];
    final point = [lat.toDouble(), lon.toDouble()];
    if (!_valid(point)) return const [];
    points.add(point);
  }
  return points;
}

List<List<double>>? _nodePoint(Map<String, dynamic> item) {
  final lat = item['lat'];
  final lon = item['lon'];
  if (lat is! num || lon is! num) return null;
  final point = [lat.toDouble(), lon.toDouble()];
  return _valid(point) ? [point] : null;
}

List<List<double>>? _path(List<List<double>> points) {
  final unique = _unique(points);
  return unique.length >= 2 ? points : null;
}

List<List<double>>? _closedFootprint(List<List<double>> points) {
  // Missing closing geometry is not permission to invent a footprint edge.
  if (points.length < 4 || !_same(points.first, points.last)) return null;
  final normalized = List<List<double>>.from(points);
  if (normalized.length > 1 && _same(normalized.first, normalized.last)) {
    normalized.removeLast();
  }
  return _unique(normalized).length >= 3 ? normalized : null;
}

List<List<double>>? _relationOuterFootprint(Object? rawMembers) {
  if (rawMembers is! List) return null;
  // V0 supports exactly one already-closed outer ring. Do not fill courtyards
  // or discard additional outers; unsupported multipolygons stay diagnostic.
  final rings = rawMembers
      .whereType<Map>()
      .where((m) => m['type'] == 'way')
      .toList();
  if (rings.length != 1 || rings.single['role'] != 'outer') return null;
  for (final member in rawMembers) {
    if (member is! Map || member['role'] != 'outer') continue;
    final footprint = _closedFootprint(_geometry(member['geometry']));
    if (footprint != null) return footprint;
  }
  return null;
}

bool _valid(List<double> point) =>
    point[0].isFinite &&
    point[1].isFinite &&
    point[0].abs() <= 90 &&
    point[1].abs() <= 180;

List<List<double>> _unique(List<List<double>> points) {
  final unique = <List<double>>[];
  for (final point in points) {
    if (!unique.any((existing) => _same(existing, point))) unique.add(point);
  }
  return unique;
}

bool _same(List<double> a, List<double> b) => a[0] == b[0] && a[1] == b[1];
