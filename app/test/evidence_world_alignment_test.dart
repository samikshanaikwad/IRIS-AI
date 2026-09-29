import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/geometry/domain/evidence_world_alignment.dart';
import 'package:iris/features/geometry/domain/relative_geometry.dart';

void main() {
  EvidenceWorldAlignment alignment({double yaw = 0, double scale = 1}) =>
      EvidenceWorldAlignment(
        caseId: 'case',
        evidenceId: 'evidence',
        translationX: 10,
        translationY: 2,
        translationZ: 4,
        yaw: yaw,
        uniformScale: scale,
        source: AlignmentSource.userSupplied,
        geometrySha256: 'a' * 64,
        roadContextFingerprint: 'b' * 64,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );

  test('applies uniform scale, yaw, then translation in world coordinates', () {
    final point = alignment(
      yaw: 3.141592653589793 / 2,
      scale: 2,
    ).transform(const RelativePoint(x: 1, y: 3, z: 0, u: 0, v: 0));
    expect(point.x, closeTo(10, 0.00001));
    expect(point.y, closeTo(8, 0.00001));
    expect(point.z, closeTo(6, 0.00001));
  });

  test(
    'records only user-supplied source and detects changed provenance as stale',
    () {
      final value = alignment();
      expect(value.source, AlignmentSource.userSupplied);
      expect(
        value.isStale(
          geometrySha256: 'a' * 64,
          roadContextFingerprint: 'b' * 64,
        ),
        isFalse,
      );
      expect(
        value.isStale(
          geometrySha256: 'c' * 64,
          roadContextFingerprint: 'b' * 64,
        ),
        isTrue,
      );
      expect(
        value.isStale(
          geometrySha256: 'a' * 64,
          roadContextFingerprint: 'd' * 64,
        ),
        isTrue,
      );
    },
  );
}
