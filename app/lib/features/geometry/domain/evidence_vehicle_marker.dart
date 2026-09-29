import '../../detection/domain/evidence_detection.dart';
import 'relative_geometry.dart';
import 'evidence_world_alignment.dart';

const eligibleVehicleClasses = <String>{
  'car',
  'motorcycle',
  'bus',
  'truck',
  'bicycle',
};

class EvidenceVehicleMarker {
  const EvidenceVehicleMarker({
    required this.detectionIndex,
    required this.className,
    required this.score,
    required this.ymin,
    required this.xmin,
    required this.ymax,
    required this.xmax,
    required this.evidenceAnchor,
    required this.worldAnchor,
  });
  final int detectionIndex;
  final String className;
  final double score, ymin, xmin, ymax, xmax;
  final RelativePoint evidenceAnchor, worldAnchor;
}

List<EvidenceVehicleMarker> deriveVehicleMarkers({
  required EvidenceDetectionAnalysis analysis,
  required RelativeGeometry geometry,
  required EvidenceWorldAlignment alignment,
}) {
  final markers = <EvidenceVehicleMarker>[];
  for (var index = 0; index < analysis.detections.length; index++) {
    final detection = analysis.detections[index];
    if (!eligibleVehicleClasses.contains(detection.className)) continue;
    final anchor = _anchorFor(detection, geometry);
    if (anchor == null) continue;
    markers.add(
      EvidenceVehicleMarker(
        detectionIndex: index,
        className: detection.className,
        score: detection.score,
        ymin: detection.ymin,
        xmin: detection.xmin,
        ymax: detection.ymax,
        xmax: detection.xmax,
        evidenceAnchor: anchor,
        worldAnchor: alignment.transform(anchor),
      ),
    );
  }
  return List.unmodifiable(markers);
}

RelativePoint? _anchorFor(
  EvidenceDetection detection,
  RelativeGeometry geometry,
) {
  final width = detection.xmax - detection.xmin,
      height = detection.ymax - detection.ymin;
  if (!(width > 0) || !(height > 0)) return null;
  final left = detection.xmin + width * .2, right = detection.xmax - width * .2;
  final top = detection.ymin + height * .5,
      bottom = detection.ymax - height * .1;
  final candidates = geometry.points
      .where((p) => p.u >= left && p.u <= right && p.v >= top && p.v <= bottom)
      .toList();
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) => a.z.compareTo(b.z));
  final point = candidates[candidates.length ~/ 2];
  if (![point.x, point.y, point.z].every((v) => v.isFinite)) return null;
  return point;
}
