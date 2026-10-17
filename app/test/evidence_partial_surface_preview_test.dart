import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/partial_surface/domain/evidence_partial_surface.dart';
import 'package:iris/features/partial_surface/presentation/evidence_partial_surface_preview.dart';

void main() {
  test(
    'preview fit compresses only an oversized nonmetric depth display range',
    () {
      final frame =
          PartialSurfacePreviewFrame.fromVertices(const <PartialSurfaceVertex>[
            PartialSurfaceVertex(x: -20, y: -10, z: 1, u: .2, v: .3, argb: 0),
            PartialSurfaceVertex(x: 20, y: 10, z: 51, u: .8, v: .7, argb: 0),
          ]);

      expect(frame.lateralSpan, closeTo(.6, 1e-12));
      expect(frame.displayDepthScale, closeTo(.012, 1e-12));
      expect(frame.centerZ, 26);
      expect(frame.centerU, .5);
      expect(frame.centerV, .5);
    },
  );

  test('preview fit leaves a compatible relative-depth range unchanged', () {
    final frame =
        PartialSurfacePreviewFrame.fromVertices(const <PartialSurfaceVertex>[
          PartialSurfaceVertex(x: -1, y: -1, z: .8, u: 0, v: 0, argb: 0),
          PartialSurfaceVertex(x: 1, y: 1, z: 1.2, u: 1, v: 1, argb: 0),
        ]);

    expect(frame.displayDepthScale, 1);
  });
}
