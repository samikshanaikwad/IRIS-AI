import 'package:flutter/foundation.dart';

import '../../evidence/domain/evidence_image.dart';
import '../domain/evidence_segmentation.dart';
import 'evidence_segmentation_service.dart';

class EvidenceSegmentationController extends ChangeNotifier {
  EvidenceSegmentationController({
    required this.evidence,
    required this.operations,
  });

  final EvidenceImage evidence;
  final EvidenceSegmentationOperations operations;
  EvidenceSegmentationSnapshot snapshot = const EvidenceSegmentationSnapshot(
    EvidenceSegmentationState.notAnalyzed,
  );
  EvidenceSegmentationCancellation? _cancellation;

  bool get busy =>
      snapshot.state == EvidenceSegmentationState.queued ||
      snapshot.state == EvidenceSegmentationState.running;
  bool get executionEnabled => operations.executionEnabled;

  Future<void> load() async {
    try {
      snapshot = await operations.load(evidence);
    } on Object {
      snapshot = const EvidenceSegmentationSnapshot(
        EvidenceSegmentationState.unavailable,
        message: 'Saved segmentation could not be read.',
      );
    }
    notifyListeners();
  }

  Future<void> analyze() async {
    if (busy) return;
    final cancellation = EvidenceSegmentationCancellation();
    _cancellation = cancellation;
    snapshot = const EvidenceSegmentationSnapshot(
      EvidenceSegmentationState.queued,
      message: 'Waiting for the single segmentation worker.',
    );
    notifyListeners();
    try {
      final analysis = await operations.analyze(
        evidence,
        cancellation: cancellation,
        onStarted: () {
          snapshot = const EvidenceSegmentationSnapshot(
            EvidenceSegmentationState.running,
            message: 'Running MobileSAM on this device…',
          );
          notifyListeners();
        },
      );
      snapshot = EvidenceSegmentationSnapshot(
        EvidenceSegmentationState.current,
        analysis: analysis,
      );
    } on EvidenceSegmentationCancelled {
      snapshot = const EvidenceSegmentationSnapshot(
        EvidenceSegmentationState.cancelled,
        message: 'Segmentation was cancelled; no mask was saved.',
      );
    } on EvidenceSegmentationUnsupported catch (error) {
      snapshot = EvidenceSegmentationSnapshot(
        EvidenceSegmentationState.unsupported,
        message: error.message,
      );
    } on EvidenceSegmentationUnavailable catch (error) {
      snapshot = EvidenceSegmentationSnapshot(
        EvidenceSegmentationState.unavailable,
        message: error.message,
      );
    } on EvidenceSegmentationRuntimeFailure catch (error) {
      snapshot = EvidenceSegmentationSnapshot(
        EvidenceSegmentationState.error,
        message: error.message,
      );
    } on Object {
      snapshot = const EvidenceSegmentationSnapshot(
        EvidenceSegmentationState.error,
        message: 'Segmentation failed; no fallback mask was saved.',
      );
    } finally {
      _cancellation = null;
      notifyListeners();
    }
  }

  void cancel() {
    _cancellation?.cancel();
    if (snapshot.state == EvidenceSegmentationState.queued) {
      snapshot = const EvidenceSegmentationSnapshot(
        EvidenceSegmentationState.cancelled,
        message: 'Queued segmentation was cancelled.',
      );
      notifyListeners();
    }
  }
}
