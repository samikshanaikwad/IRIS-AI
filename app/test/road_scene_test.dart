import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/location/domain/road_context.dart';

void main() {
  test('road context preserves local metric coordinates and missing width', () {
    const segment = RoadSegment(
      id: 'way-1',
      roadClass: 'residential',
      coordinates: [[12.0, 77.0], [12.001, 77.001]],
      localCoordinates: [[0.0, 0.0], [109.0, 111.0]],
    );
    expect(segment.localCoordinates.last, [109.0, 111.0]);
    expect(segment.width, isNull);
  });

  test('road context distinguishes map geometry from image geometry', () {
    final context = RoadContext(
      caseId: 'case', latitude: 12, longitude: 77, status: 'AVAILABLE',
      retrievedAt: DateTime(2026), roads: [],
    );
    expect(context.provider, contains('OpenStreetMap'));
    expect(context.status, 'AVAILABLE');
  });
}
