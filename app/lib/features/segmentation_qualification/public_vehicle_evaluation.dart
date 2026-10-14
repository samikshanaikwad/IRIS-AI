import '../detection/domain/evidence_detection.dart';
import '../evidence/domain/image_coordinate_contract.dart';
import 'segmentation_prompt_box.dart';

/// Rights-cleared public images governed by
/// `ml/segmentation/qualification/public_vehicle_evaluation.v1.json`.
///
/// These assets exist only in the Android debug source set. They are never
/// imported into an IRIS case or treated as incident evidence.
class PublicVehicleEvaluationImage {
  const PublicVehicleEvaluationImage({
    required this.id,
    required this.assetName,
    required this.vehicleClass,
    required this.scenario,
    required this.sourcePage,
    required this.author,
    required this.license,
    required this.sha256,
  });

  final String id;
  final String assetName;
  final String vehicleClass;
  final String scenario;
  final String sourcePage;
  final String author;
  final String license;
  final String sha256;

  Map<String, Object> toQualificationJson() => <String, Object>{
    'id': id,
    'asset_name': assetName,
    'vehicle_class': vehicleClass,
    'scenario': scenario,
    'source': sourcePage,
    'author': author,
    'license_or_permission': license,
    'rights_status': 'CLEARED',
    'synthetic': false,
    'sha256': sha256,
  };
}

const publicVehicleEvaluationImages = <PublicVehicleEvaluationImage>[
  PublicVehicleEvaluationImage(
    id: 'motorcycle-clean',
    assetName: 'motorcycle_clean.jpg',
    vehicleClass: 'motorcycle',
    scenario:
        'single intact motorcycle with a visually complex backlit background',
    sourcePage:
        'https://commons.wikimedia.org/wiki/File:Parked_Motorcycle_(Unsplash).jpg',
    author: 'Igor Ovsyannykov',
    license: 'CC0 1.0',
    sha256: '01d636fa67d18e048ce009022c7df99185e3646874840f2e15f642451e789059',
  ),
  PublicVehicleEvaluationImage(
    id: 'motorcycle-damaged',
    assetName: 'motorcycle_damaged.jpg',
    vehicleClass: 'motorcycle',
    scenario: 'visibly damaged motorcycle at small scale in an incident scene',
    sourcePage:
        'https://commons.wikimedia.org/wiki/File:Motorcycle_Accident.jpg',
    author: 'Jack from Mohrsville Pa., USA',
    license: 'CC BY-SA 2.0',
    sha256: '718294a6042acca0e8d176107b6a1c9069c95d36d2b2b8c18b427a999dd9314d',
  ),
  PublicVehicleEvaluationImage(
    id: 'motorcycle-partial-edge',
    assetName: 'motorcycles_multiple.png',
    vehicleClass: 'motorcycle',
    scenario:
        'partly frame-cropped motorcycle with luggage and background clutter',
    sourcePage:
        'https://commons.wikimedia.org/wiki/File:Motorcycle_parking_001.png',
    author: 'Gmbo 2013',
    license: 'CC0 1.0',
    sha256: 'd1978e268574e3bae0cdaa09b1d5e292b302a98d16f21de882e346ea7a312149',
  ),
  PublicVehicleEvaluationImage(
    id: 'motorcycles-multiple',
    assetName: 'motorcycles_multiple_real.jpg',
    vehicleClass: 'motorcycle',
    scenario: 'three adjacent motorcycles for multiple-instance separation',
    sourcePage:
        'https://commons.wikimedia.org/wiki/File:Parked_motorcycles.jpg',
    author: 'ANBI',
    license: 'CC BY-SA 3.0',
    sha256: 'e89f7cc65abf5403658a20ba76a262e8cf738cdef5d43b794ce31d5ee8426fa0',
  ),
  PublicVehicleEvaluationImage(
    id: 'car-full',
    assetName: 'car_full.jpg',
    vehicleClass: 'car',
    scenario:
        'large frontal car with other partly visible vehicles in the background',
    sourcePage: 'https://commons.wikimedia.org/wiki/File:Ferrari_F50_Front.jpg',
    author: 'Alzy007',
    license: 'Public domain release by copyright holder',
    sha256: '3cbd6d96b14ffcb21bb187eda4932b2ec593165c229fdc9c235a968bd777f1de',
  ),
  PublicVehicleEvaluationImage(
    id: 'car-partial-edge',
    assetName: 'car_clean.jpg',
    vehicleClass: 'car',
    scenario: 'close, frame-cropped car body for partial-object behavior',
    sourcePage:
        'https://commons.wikimedia.org/wiki/File:Yellow_car_side_(Unsplash).jpg',
    author: 'Benjamin Nwaneampeh',
    license: 'CC0 1.0',
    sha256: '8548381d567af0d6d6471b5764e51b875a2b6b849022d851d84a90009e5428be',
  ),
  PublicVehicleEvaluationImage(
    id: 'cars-dense-traffic',
    assetName: 'cars_traffic.jpg',
    vehicleClass: 'car',
    scenario: 'dense multi-vehicle traffic with occlusion and scale variation',
    sourcePage:
        'https://commons.wikimedia.org/wiki/File:Driving_Cars_in_a_Traffic_Jam.jpg',
    author: 'epSos.de',
    license: 'CC BY 2.0',
    sha256: '30ae6ce002d4431b1f19bba5bde67811a8d7dbe62f26093e64cd6c1e12339ed5',
  ),
];

/// Converts only genuine current TASK007 detections of the governed target
/// class into MobileSAM prompts. No detector box means no segmentation run.
List<SegmentationPromptBox> publicEvaluationPrompts({
  required String vehicleClass,
  required Iterable<EvidenceDetection> detections,
  required ImageCoordinateMetadata metadata,
  int maximum = 12,
}) {
  final eligible =
      detections
          .where((detection) => detection.className == vehicleClass)
          .toList(growable: false)
        ..sort((left, right) => right.score.compareTo(left.score));
  final prompts = <SegmentationPromptBox>[];
  for (final detection in eligible) {
    if (prompts.length == maximum) break;
    try {
      prompts.add(
        SegmentationPromptBox.fromDetection(
          detection: detection,
          metadata: metadata,
        ),
      );
    } on FormatException {
      // A malformed or letterbox-only real detection is rejected; it is never
      // replaced with a synthetic prompt.
    }
  }
  return prompts;
}
