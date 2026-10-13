import 'package:flutter_test/flutter_test.dart';
import 'package:iris/core/domain/case_local_world.dart';
import 'package:iris/features/geometry/domain/evidence_world_alignment.dart';
import 'package:iris/features/geometry/domain/relative_geometry.dart';

void main() {
  EvidenceWorldAlignment alignment({
    double yaw = 0,
    double scale = 1,
    String? geometrySha256,
    String? roadContextFingerprint,
    String? worldFrameFingerprint,
    String? provenanceVersion,
  }) => EvidenceWorldAlignment(
    caseId: 'case',
    evidenceId: 'evidence',
    translationX: 10,
    translationY: 2,
    translationZ: 4,
    yaw: yaw,
    uniformScale: scale,
    source: AlignmentSource.userSupplied,
    geometrySha256: geometrySha256 ?? 'a' * 64,
    roadContextFingerprint: roadContextFingerprint ?? 'b' * 64,
    worldFrameFingerprint: worldFrameFingerprint,
    provenanceVersion: provenanceVersion,
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

  group('stable alignment provenance', () {
    final frame = CaseLocalWorldFrame.fingerprint(
      caseId: 'case',
      originLatitude: 12.3,
      originLongitude: 45.6,
    );

    EvidenceWorldAlignment current() => alignment(
      worldFrameFingerprint: frame,
      provenanceVersion: EvidenceWorldAlignment.currentProvenanceVersion,
    );

    test('same location survives additional, reordered or refreshed roads', () {
      final value = current();
      for (final changedRoads in ['c' * 64, 'd' * 64, 'e' * 64]) {
        expect(
          value.provenanceStatus(
            geometrySha256: 'a' * 64,
            roadContextFingerprint: changedRoads,
            worldFrameFingerprint: frame,
          ),
          AlignmentProvenanceStatus.current,
        );
      }
    });

    test('different confirmed location invalidates alignment', () {
      expect(
        current().provenanceStatus(
          geometrySha256: 'a' * 64,
          roadContextFingerprint: 'b' * 64,
          worldFrameFingerprint: CaseLocalWorldFrame.fingerprint(
            caseId: 'case',
            originLatitude: 12.4,
            originLongitude: 45.6,
          ),
        ),
        AlignmentProvenanceStatus.worldFrameChanged,
      );
    });

    test('changed evidence geometry invalidates alignment independently', () {
      expect(
        current().provenanceStatus(
          geometrySha256: 'c' * 64,
          roadContextFingerprint: 'b' * 64,
          worldFrameFingerprint: frame,
        ),
        AlignmentProvenanceStatus.geometryChanged,
      );
    });

    test('legacy provenance is accepted only for an exact road snapshot', () {
      final legacy = alignment();
      expect(
        legacy.provenanceStatus(
          geometrySha256: 'a' * 64,
          roadContextFingerprint: 'b' * 64,
          worldFrameFingerprint: frame,
        ),
        AlignmentProvenanceStatus.legacyCurrentRoadProven,
      );
      expect(
        legacy.provenanceStatus(
          geometrySha256: 'a' * 64,
          roadContextFingerprint: 'd' * 64,
          worldFrameFingerprint: frame,
        ),
        AlignmentProvenanceStatus.legacyLocationUnproven,
      );
    });

    test('unsupported partial provenance never resurrects alignment', () {
      expect(
        alignment(
          provenanceVersion: EvidenceWorldAlignment.currentProvenanceVersion,
        ).provenanceStatus(
          geometrySha256: 'a' * 64,
          roadContextFingerprint: 'b' * 64,
          worldFrameFingerprint: frame,
        ),
        AlignmentProvenanceStatus.unsupportedContract,
      );
    });
  });
}
