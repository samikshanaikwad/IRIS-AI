import 'package:flutter/foundation.dart';
import '../../evidence/domain/evidence_image.dart';
import '../domain/evidence_detection.dart';
import 'evidence_detection_service.dart';

class EvidenceDetectionController extends ChangeNotifier {
  EvidenceDetectionController({
    required this.evidence,
    required this.operations,
  });
  final EvidenceImage evidence;
  final EvidenceDetectionOperations operations;
  EvidenceDetectionSnapshot snapshot = const EvidenceDetectionSnapshot(
    DetectionState.notAnalyzed,
  );
  bool busy = false;
  String? error;
  Future<void> load() async {
    try {
      snapshot = await operations.load(evidence);
    } catch (_) {
      snapshot = const EvidenceDetectionSnapshot(DetectionState.unavailable);
    }
    notifyListeners();
  }

  Future<void> analyze() async {
    if (busy) return;
    busy = true;
    error = null;
    snapshot = const EvidenceDetectionSnapshot(DetectionState.detecting);
    notifyListeners();
    try {
      final a = await operations.analyze(evidence);
      snapshot = EvidenceDetectionSnapshot(
        DetectionState.complete,
        analysis: a,
      );
    } catch (e) {
      error = 'Scene object detection could not be completed.';
      snapshot = EvidenceDetectionSnapshot(
        DetectionState.error,
        message: error,
      );
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
