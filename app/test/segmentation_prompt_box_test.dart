import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/detection/domain/evidence_detection.dart';
import 'package:iris/features/evidence/domain/image_coordinate_contract.dart';
import 'package:iris/features/segmentation_qualification/segmentation_prompt_box.dart';

void main() {
  EvidenceDetection detection({
    int classId = 3,
    String className = 'motorcycle',
    double ymin = 0.25,
    double xmin = 0.10,
    double ymax = 0.75,
    double xmax = 0.90,
  }) => EvidenceDetection(
    classId: classId,
    className: className,
    score: 0.82,
    ymin: ymin,
    xmin: xmin,
    ymax: ymax,
    xmax: xmax,
  );

  ImageCoordinateMetadata metadata(IrisExifOrientation orientation) =>
      ImageCoordinateMetadata.create(
        raw: const ImageExtent(1600, 900),
        orientation: orientation,
        canvas: const ImageExtent(320, 320),
        mode: RasterResizeMode.containLetterbox,
        rounding: RasterRounding.floor,
      );

  test('maps detector letterbox box through raw into oriented pixels', () {
    final prompt = SegmentationPromptBox.fromDetection(
      detection: detection(),
      metadata: metadata(IrisExifOrientation.normal),
    );
    expect(prompt.left, closeTo(160, 1e-8));
    expect(prompt.top, closeTo(50, 1e-8));
    expect(prompt.right, closeTo(1440, 1e-8));
    expect(prompt.bottom, closeTo(850, 1e-8));
  });

  test('maps a mirrored EXIF detector box into oriented image coordinates', () {
    final prompt = SegmentationPromptBox.fromDetection(
      detection: detection(xmin: 0.15, xmax: 0.75),
      metadata: metadata(IrisExifOrientation.mirrorHorizontal),
    );
    expect(prompt.left, closeTo(240, 1e-8));
    expect(prompt.right, closeTo(1200, 1e-8));
    expect(prompt.top, closeTo(50, 1e-8));
    expect(prompt.bottom, closeTo(850, 1e-8));
  });

  test('maps quarter-turn orientation without swapping detector axes', () {
    final prompt = SegmentationPromptBox.fromDetection(
      detection: detection(),
      metadata: metadata(IrisExifOrientation.rotate90Clockwise),
    );
    expect(prompt.left, closeTo(0, 1e-8));
    expect(prompt.top, closeTo(400, 1e-8));
    expect(prompt.right, closeTo(900, 1e-8));
    expect(prompt.bottom, closeTo(1200, 1e-8));
  });

  test('clips only letterbox spill at image edge and preserves valid box', () {
    final prompt = SegmentationPromptBox.fromDetection(
      detection: detection(ymin: 0.0, ymax: 0.5),
      metadata: metadata(IrisExifOrientation.normal),
    );
    expect(prompt.top, closeTo(0, 1e-8));
    expect(prompt.bottom, closeTo(450, 1e-8));
  });

  test('rejects non-eligible, mismatched and invalid detections', () {
    expect(
      () => SegmentationPromptBox.fromDetection(
        detection: detection(classId: 0, className: 'person'),
        metadata: metadata(IrisExifOrientation.normal),
      ),
      throwsFormatException,
    );
    expect(
      () => SegmentationPromptBox.fromDetection(
        detection: detection(classId: 3, className: 'car'),
        metadata: metadata(IrisExifOrientation.normal),
      ),
      throwsFormatException,
    );
    expect(
      () => SegmentationPromptBox.fromDetection(
        detection: detection(xmin: 0.8, xmax: 0.2),
        metadata: metadata(IrisExifOrientation.normal),
      ),
      throwsFormatException,
    );
  });
}
