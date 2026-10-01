import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/location/application/case_location_service.dart';
import 'package:iris/features/location/domain/case_location.dart';
import 'package:iris/features/location/domain/environment_parser.dart';

void main() {
  const originLat = 12.0, originLon = 77.0;

  ParsedEnvironment parse(List<dynamic> elements) => parseEnvironmentElements(
    elements: elements,
    originLatitude: originLat,
    originLongitude: originLon,
  );

  test('accepts a simple building way without name or height', () {
    final result = parse([
      {
        'type': 'way',
        'id': 7,
        'tags': {'building': 'yes'},
        'geometry': [
          {'lat': 12.0, 'lon': 77.0},
          {'lat': 12.0, 'lon': 77.001},
          {'lat': 12.001, 'lon': 77.001},
          {'lat': 12.0, 'lon': 77.0},
        ],
      },
    ]);
    expect(result.features.single.id, 'way/7');
    expect(result.features.single.featureType, 'building');
    expect(result.features.single.coordinates, hasLength(3));
    expect(result.diagnostics.parsedBuildings, 1);
  });

  test(
    'rejects malformed building geometry without converting it to a feature',
    () {
      final result = parse([
        {
          'type': 'way',
          'id': 7,
          'tags': {'building': 'yes'},
          'geometry': [
            {'lat': 12.0, 'lon': 77.0},
            {'lat': 12.0, 'lon': 77.0},
          ],
        },
      ]);
      expect(result.features, isEmpty);
      expect(result.diagnostics.taggedBuildingWays, 1);
      expect(result.diagnostics.parsedBuildings, 0);
    },
  );

  test('accepts mapped tree nodes and supported barrier paths', () {
    final result = parse([
      {
        'type': 'node',
        'id': 8,
        'lat': 12.0001,
        'lon': 77.0001,
        'tags': {'natural': 'tree'},
      },
      {
        'type': 'way',
        'id': 9,
        'tags': {'barrier': 'guard_rail'},
        'geometry': [
          {'lat': 12.0, 'lon': 77.0},
          {'lat': 12.0, 'lon': 77.001},
        ],
      },
    ]);
    expect(result.diagnostics.parsedTrees, 1);
    expect(result.diagnostics.parsedBarriers, 1);
    expect(
      result.features.map((item) => item.featureType),
      containsAll(['tree', 'barrier']),
    );
  });

  test(
    'uses a relation outer member only when it contains a valid footprint',
    () {
      final result = parse([
        {
          'type': 'relation',
          'id': 10,
          'tags': {'building': 'yes', 'type': 'multipolygon'},
          'members': [
            {
              'type': 'way',
              'role': 'outer',
              'geometry': [
                {'lat': 12.0, 'lon': 77.0},
                {'lat': 12.0, 'lon': 77.001},
                {'lat': 12.001, 'lon': 77.001},
                {'lat': 12.0, 'lon': 77.0},
              ],
            },
          ],
        },
      ]);
      expect(result.diagnostics.parsedBuildings, 1);
      expect(result.features.single.elementType, 'relation');
    },
  );

  test('returns honest zero counts for a successful empty response', () {
    final result = parse(const []);
    expect(result.features, isEmpty);
    expect(result.diagnostics.totalElements, 0);
    expect(result.diagnostics.parsedBuildings, 0);
  });

  test(
    'environment query is bounded and uses confirmed latitude then longitude',
    () {
      final query = CaseLocationService.environmentQuery(
        CaseLocation(
          caseId: 'test-case',
          latitude: 12.5,
          longitude: 77.5,
          source: CaseLocationSource.mapSelection,
          updatedAt: DateTime.utc(2026),
        ),
      );
      expect(query, contains('around:150,12.5,77.5'));
      expect(query, contains('way(around:150,12.5,77.5)["building"]'));
      expect(query, contains('relation(around:150,12.5,77.5)["building"]'));
      expect(query, contains('out tags geom;'));
    },
  );
}
