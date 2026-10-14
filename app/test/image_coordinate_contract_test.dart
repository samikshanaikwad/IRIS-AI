import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/evidence/domain/image_coordinate_contract.dart';

void main() {
  const raw = ImageExtent(400, 300);
  const epsilon = 1e-8;

  test('all eight EXIF orientations are invertible', () {
    for (final orientation in IrisExifOrientation.values) {
      final metadata = ImageCoordinateMetadata.create(
        raw: raw,
        orientation: orientation,
        canvas: const ImageExtent(640, 640),
        mode: RasterResizeMode.containLetterbox,
        rounding: RasterRounding.nearest,
      );
      final samples = <ImageCoordinate>[
        const ImageCoordinate(0, 0),
        const ImageCoordinate(400, 0),
        const ImageCoordinate(0, 300),
        const ImageCoordinate(400, 300),
        const ImageCoordinate(117.25, 212.75),
      ];
      for (final sample in samples) {
        final canvas = metadata.rawPointToCanvas(sample);
        final restored = metadata.canvasPointToRaw(canvas);
        expect(restored.x, closeTo(sample.x, epsilon));
        expect(restored.y, closeTo(sample.y, epsilon));
      }
    }
  });

  test('mirrored orientations map corners according to EXIF', () {
    ImageCoordinate map(IrisExifOrientation orientation, double x, double y) =>
        ImageCoordinateMetadata.create(
          raw: raw,
          orientation: orientation,
          canvas: orientation.swapsAxes ? const ImageExtent(300, 400) : raw,
          mode: RasterResizeMode.containLetterbox,
          rounding: RasterRounding.nearest,
        ).rawPointToCanvas(ImageCoordinate(x, y));

    expect(map(IrisExifOrientation.mirrorHorizontal, 0, 0).x, 400);
    expect(map(IrisExifOrientation.mirrorVertical, 0, 0).y, 300);
    final transpose = map(IrisExifOrientation.transpose, 400, 300);
    expect(transpose.x, 300);
    expect(transpose.y, 400);
    final transverse = map(IrisExifOrientation.transverse, 0, 0);
    expect(transverse.x, 300);
    expect(transverse.y, 400);
  });

  test(
    'portrait and landscape letterboxes preserve exact runtime rounding',
    () {
      final landscape = ImageCoordinateMetadata.create(
        raw: const ImageExtent(403, 301),
        orientation: IrisExifOrientation.normal,
        canvas: const ImageExtent(320, 320),
        mode: RasterResizeMode.containLetterbox,
        rounding: RasterRounding.floor,
      );
      expect(landscape.placement.resizedWidth, 320);
      expect(landscape.placement.resizedHeight, 239);
      expect(landscape.placement.offsetY, 40);

      final portrait = ImageCoordinateMetadata.create(
        raw: const ImageExtent(301, 403),
        orientation: IrisExifOrientation.normal,
        canvas: const ImageExtent(518, 518),
        mode: RasterResizeMode.containLetterbox,
        rounding: RasterRounding.nearest,
      );
      expect(portrait.placement.resizedWidth, 387);
      expect(portrait.placement.resizedHeight, 518);
      expect(portrait.placement.offsetX, 65);
    },
  );

  test('cover mode represents deterministic center cropping and inversion', () {
    final metadata = ImageCoordinateMetadata.create(
      raw: const ImageExtent(400, 200),
      orientation: IrisExifOrientation.normal,
      canvas: const ImageExtent(200, 200),
      mode: RasterResizeMode.coverCrop,
      rounding: RasterRounding.nearest,
    );
    expect(metadata.placement.resizedWidth, 400);
    expect(metadata.placement.resizedHeight, 200);
    expect(metadata.placement.offsetX, -100);
    final center = metadata.rawPointToCanvas(const ImageCoordinate(200, 100));
    expect(center.x, 100);
    expect(center.y, 100);
    final restored = metadata.canvasPointToRaw(center);
    expect(restored.x, closeTo(200, epsilon));
    expect(restored.y, closeTo(100, epsilon));
  });

  test('padding and out-of-image points are rejected', () {
    final metadata = ImageCoordinateMetadata.create(
      raw: raw,
      orientation: IrisExifOrientation.normal,
      canvas: const ImageExtent(640, 640),
      mode: RasterResizeMode.containLetterbox,
      rounding: RasterRounding.nearest,
    );
    expect(
      () => metadata.canvasPointToRaw(const ImageCoordinate(20, 20)),
      throwsFormatException,
    );
    expect(
      () => metadata.rawPointToCanvas(const ImageCoordinate(-1, 20)),
      throwsFormatException,
    );
  });

  test('detector canvas maps to depth canvas through oriented original', () {
    final detector = ImageCoordinateMetadata.create(
      raw: const ImageExtent(403, 301),
      orientation: IrisExifOrientation.rotate90Clockwise,
      canvas: const ImageExtent(320, 320),
      mode: RasterResizeMode.containLetterbox,
      rounding: RasterRounding.floor,
    );
    final depth = ImageCoordinateMetadata.create(
      raw: const ImageExtent(403, 301),
      orientation: IrisExifOrientation.rotate90Clockwise,
      canvas: const ImageExtent(518, 518),
      mode: RasterResizeMode.containLetterbox,
      rounding: RasterRounding.nearest,
    );
    final detectorPoint = detector.rawToNormalizedCanvas(
      const ImageCoordinate(137.5, 91.25),
    );
    final depthPoint = detector.normalizedCanvasTo(
      point: detectorPoint,
      target: depth,
    );
    final restored = depth.normalizedCanvasToRaw(depthPoint);
    expect(restored.x, closeTo(137.5, epsilon));
    expect(restored.y, closeTo(91.25, epsilon));
  });

  test('metadata serialization is validated and deterministic', () {
    final metadata = ImageCoordinateMetadata.create(
      raw: const ImageExtent(1024, 768),
      orientation: IrisExifOrientation.transverse,
      canvas: const ImageExtent(518, 518),
      mode: RasterResizeMode.containLetterbox,
      rounding: RasterRounding.nearest,
    );
    final restored = ImageCoordinateMetadata.fromJson(metadata.toJson());
    expect(restored.toJson(), metadata.toJson());
    expect(
      () => ImageCoordinateMetadata.fromJson({
        ...metadata.toJson(),
        'contractVersion': 'unknown',
      }),
      throwsFormatException,
    );
    expect(
      () => ImageCoordinateMetadata.fromJson({
        ...metadata.toJson(),
        'exifOrientation': 9,
      }),
      throwsFormatException,
    );
  });
}
