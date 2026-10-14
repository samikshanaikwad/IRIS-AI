import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/detection/domain/evidence_detection.dart';
import 'package:iris/features/evidence/domain/image_coordinate_contract.dart';
import 'package:iris/features/segmentation_qualification/public_vehicle_evaluation.dart';

void main() {
  test('debug inventory stays identical to governed public manifest', () {
    final manifestFile = File(
      '../ml/segmentation/qualification/public_vehicle_evaluation.v1.json',
    );
    expect(manifestFile.existsSync(), isTrue);
    final manifest = jsonDecode(manifestFile.readAsStringSync()) as Map;
    final images = (manifest['images'] as List).cast<Map<String, Object?>>();
    expect(images.length, publicVehicleEvaluationImages.length);
    for (var index = 0; index < images.length; index++) {
      final governed = images[index];
      final inApp = publicVehicleEvaluationImages[index];
      expect(inApp.id, governed['id']);
      expect(inApp.assetName, governed['asset_name']);
      expect(inApp.vehicleClass, governed['supported_vehicle_class']);
      expect(inApp.scenario, governed['scenario']);
      expect(inApp.sourcePage, governed['source_page']);
      expect(inApp.author, governed['author']);
      expect(inApp.license, governed['license']);
      expect(inApp.sha256, governed['sha256']);
      expect(governed['rights_status'], 'CLEARED');
      expect(governed['synthetic'], isFalse);
    }
  });

  test('only genuine matching detector classes become prompts', () {
    final metadata = ImageCoordinateMetadata.create(
      raw: const ImageExtent(640, 480),
      orientation: IrisExifOrientation.normal,
      canvas: const ImageExtent(320, 320),
      mode: RasterResizeMode.containLetterbox,
      rounding: RasterRounding.floor,
    );
    final detections = <EvidenceDetection>[
      const EvidenceDetection(
        classId: 2,
        className: 'car',
        score: 0.8,
        ymin: 0.2,
        xmin: 0.1,
        ymax: 0.7,
        xmax: 0.8,
      ),
      const EvidenceDetection(
        classId: 3,
        className: 'motorcycle',
        score: 0.9,
        ymin: 0.25,
        xmin: 0.2,
        ymax: 0.65,
        xmax: 0.7,
      ),
    ];
    final prompts = publicEvaluationPrompts(
      vehicleClass: 'motorcycle',
      detections: detections,
      metadata: metadata,
    );
    expect(prompts, hasLength(1));
    expect(prompts.single.className, 'motorcycle');
  });

  test('no detector match produces no synthetic segmentation prompt', () {
    final prompts = publicEvaluationPrompts(
      vehicleClass: 'motorcycle',
      detections: const <EvidenceDetection>[],
      metadata: ImageCoordinateMetadata.create(
        raw: const ImageExtent(640, 480),
        orientation: IrisExifOrientation.normal,
        canvas: const ImageExtent(320, 320),
        mode: RasterResizeMode.containLetterbox,
        rounding: RasterRounding.floor,
      ),
    );
    expect(prompts, isEmpty);
  });
}
