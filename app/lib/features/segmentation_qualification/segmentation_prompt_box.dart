import '../detection/domain/evidence_detection.dart';
import '../evidence/domain/image_coordinate_contract.dart';

/// A real TASK007 rectangle mapped into MobileSAM's oriented-original frame.
/// This carries no mask or claim that the rectangle itself is a segmentation.
class SegmentationPromptBox {
  const SegmentationPromptBox({
    required this.classId,
    required this.className,
    required this.score,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  static const supportedClasses = <int, String>{
    1: 'bicycle',
    2: 'car',
    3: 'motorcycle',
    5: 'bus',
    7: 'truck',
  };

  final int classId;
  final String className;
  final double score;
  final double left, top, right, bottom;

  static SegmentationPromptBox fromDetection({
    required EvidenceDetection detection,
    required ImageCoordinateMetadata metadata,
  }) {
    if (metadata.contractVersion != IrisImageCoordinateContract.version) {
      throw const FormatException('Unsupported image-coordinate contract.');
    }
    if (supportedClasses[detection.classId] != detection.className) {
      throw const FormatException('Detection class is not eligible.');
    }
    final values = <double>[
      detection.xmin,
      detection.ymin,
      detection.xmax,
      detection.ymax,
      detection.score,
    ];
    if (values.any((value) => !value.isFinite) ||
        detection.score < 0.30 ||
        detection.score > 1 ||
        detection.xmin < 0 ||
        detection.ymin < 0 ||
        detection.xmax > 1 ||
        detection.ymax > 1 ||
        detection.xmin >= detection.xmax ||
        detection.ymin >= detection.ymax) {
      throw const FormatException('Detection box is invalid.');
    }

    // Detector boxes are normalized against the exact 320x320 letterbox.
    // Intersect with its image-content rectangle first: letterbox-only
    // corners are not image coordinates and must not leak into a prompt.
    final placement = metadata.placement;
    final canvasLeft = detection.xmin * placement.canvas.width;
    final canvasTop = detection.ymin * placement.canvas.height;
    final canvasRight = detection.xmax * placement.canvas.width;
    final canvasBottom = detection.ymax * placement.canvas.height;
    final clippedLeft = canvasLeft < placement.imageContent.left
        ? placement.imageContent.left
        : canvasLeft;
    final clippedTop = canvasTop < placement.imageContent.top
        ? placement.imageContent.top
        : canvasTop;
    final clippedRight = canvasRight > placement.imageContent.right
        ? placement.imageContent.right
        : canvasRight;
    final clippedBottom = canvasBottom > placement.imageContent.bottom
        ? placement.imageContent.bottom
        : canvasBottom;
    if (clippedLeft >= clippedRight || clippedTop >= clippedBottom) {
      throw const FormatException('Detection box contains no image pixels.');
    }

    final rawCorners = <ImageCoordinate>[
      metadata.canvasPointToRaw(ImageCoordinate(clippedLeft, clippedTop)),
      metadata.canvasPointToRaw(ImageCoordinate(clippedRight, clippedTop)),
      metadata.canvasPointToRaw(ImageCoordinate(clippedLeft, clippedBottom)),
      metadata.canvasPointToRaw(ImageCoordinate(clippedRight, clippedBottom)),
    ];
    final oriented = rawCorners.map(metadata.rawToOriented.map).toList();
    final left = oriented.map((point) => point.x).reduce(_min);
    final top = oriented.map((point) => point.y).reduce(_min);
    final right = oriented.map((point) => point.x).reduce(_max);
    final bottom = oriented.map((point) => point.y).reduce(_max);
    if (left < 0 ||
        top < 0 ||
        right > metadata.oriented.width ||
        bottom > metadata.oriented.height ||
        left >= right ||
        top >= bottom) {
      throw const FormatException('Mapped detection box is outside the image.');
    }
    return SegmentationPromptBox(
      classId: detection.classId,
      className: detection.className,
      score: detection.score,
      left: left,
      top: top,
      right: right,
      bottom: bottom,
    );
  }

  Map<String, Object> toChannelValue() => <String, Object>{
    'classId': classId,
    'className': className,
    'score': score,
    'box': <double>[left, top, right, bottom],
  };
}

double _min(double left, double right) => left < right ? left : right;
double _max(double left, double right) => left > right ? left : right;
