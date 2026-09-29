import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/detection/domain/evidence_detection.dart';
import 'package:iris/features/geometry/domain/evidence_vehicle_marker.dart';
import 'package:iris/features/geometry/domain/evidence_world_alignment.dart';
import 'package:iris/features/geometry/domain/relative_geometry.dart';

void main() {
  final geometry = RelativeGeometry(
    evidenceId: 'e',
    depthSha256: 'a' * 64,
    depthAnalyzedAt: DateTime.utc(2026),
    width: 100,
    height: 100,
    points: const [
      RelativePoint(x: 1, y: 0, z: 2, u: .3, v: .7),
      RelativePoint(x: 2, y: 0, z: 4, u: .31, v: .75),
      RelativePoint(x: 3, y: 0, z: 6, u: .32, v: .8),
    ],
  );
  final alignment = EvidenceWorldAlignment(
    caseId: 'c',
    evidenceId: 'e',
    translationX: 10,
    translationY: 0,
    translationZ: 20,
    yaw: 0,
    uniformScale: 2,
    source: AlignmentSource.userSupplied,
    geometrySha256: 'b' * 64,
    roadContextFingerprint: 'c' * 64,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );

  test(
    'accepts eligible classes, excludes people, and keeps detections separate',
    () {
      final result = deriveVehicleMarkers(
        analysis: EvidenceDetectionAnalysis(
          id: 'a',
          evidenceId: 'e',
          evidenceSha256: 'd' * 64,
          detectorSha256: 'e' * 64,
          thresholdPolicyVersion: 'v1-score-threshold-0.30',
          analyzedAt: DateTime.utc(2026),
          inferenceMs: 1,
          detections: const [
            EvidenceDetection(
              classId: 2,
              className: 'car',
              score: .8,
              ymin: .5,
              xmin: .2,
              ymax: .9,
              xmax: .4,
            ),
            EvidenceDetection(
              classId: 0,
              className: 'person',
              score: .9,
              ymin: .5,
              xmin: .2,
              ymax: .9,
              xmax: .4,
            ),
            EvidenceDetection(
              classId: 3,
              className: 'motorcycle',
              score: .7,
              ymin: .5,
              xmin: .2,
              ymax: .9,
              xmax: .4,
            ),
          ],
        ),
        geometry: geometry,
        alignment: alignment,
      );
      expect(result, hasLength(2));
      expect(
        result.map((m) => m.className),
        containsAll(<String>['car', 'motorcycle']),
      );
      expect(result.first.worldAnchor.x, closeTo(14, .0001));
    },
  );

  test(
    'returns no fabricated marker when the robust box region has no geometry',
    () {
      final result = deriveVehicleMarkers(
        analysis: EvidenceDetectionAnalysis(
          id: 'a',
          evidenceId: 'e',
          evidenceSha256: 'd' * 64,
          detectorSha256: 'e' * 64,
          thresholdPolicyVersion: 'v1-score-threshold-0.30',
          analyzedAt: DateTime.utc(2026),
          inferenceMs: 1,
          detections: const [
            EvidenceDetection(
              classId: 2,
              className: 'car',
              score: .8,
              ymin: .0,
              xmin: .8,
              ymax: .1,
              xmax: .9,
            ),
          ],
        ),
        geometry: geometry,
        alignment: alignment,
      );
      expect(result, isEmpty);
    },
  );
}
