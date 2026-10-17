import 'package:flutter/foundation.dart';

import '../../evidence/domain/evidence_image.dart';
import '../domain/evidence_partial_surface.dart';
import 'evidence_partial_surface_service.dart';

class EvidencePartialSurfaceController extends ChangeNotifier {
  EvidencePartialSurfaceController({
    required this.evidence,
    required this.operations,
  });

  final EvidenceImage evidence;
  final EvidencePartialSurfaceOperations operations;
  EvidencePartialSurfaceSnapshot snapshot =
      const EvidencePartialSurfaceSnapshot(
        EvidencePartialSurfaceState.notGenerated,
      );
  bool busy = false;
  EvidencePartialSurfaceCancellation? _cancellation;

  bool get executionEnabled => operations.executionEnabled;

  Future<void> load() async {
    try {
      snapshot = await operations.load(evidence);
    } on Object {
      snapshot = const EvidencePartialSurfaceSnapshot(
        EvidencePartialSurfaceState.unavailable,
        message: 'Partial-surface data is unavailable.',
      );
    }
    notifyListeners();
  }

  Future<void> generate() async {
    if (busy) return;
    busy = true;
    final cancellation = EvidencePartialSurfaceCancellation();
    _cancellation = cancellation;
    snapshot = const EvidencePartialSurfaceSnapshot(
      EvidencePartialSurfaceState.generating,
    );
    notifyListeners();
    try {
      final analysis = await operations.generate(
        evidence,
        cancellation: cancellation,
      );
      snapshot = EvidencePartialSurfaceSnapshot(
        EvidencePartialSurfaceState.current,
        analysis: analysis,
      );
    } on EvidencePartialSurfaceCancelled {
      snapshot = const EvidencePartialSurfaceSnapshot(
        EvidencePartialSurfaceState.cancelled,
        message:
            'Partial-surface generation cancelled; no new artifact was saved.',
      );
    } on EvidencePartialSurfaceInsufficient catch (error) {
      snapshot = EvidencePartialSurfaceSnapshot(
        EvidencePartialSurfaceState.insufficientEvidence,
        message: error.message,
      );
    } on Object catch (error) {
      snapshot = EvidencePartialSurfaceSnapshot(
        EvidencePartialSurfaceState.error,
        message:
            'Partial-surface generation failed; no fallback surface was saved. ($error)',
      );
    } finally {
      busy = false;
      _cancellation = null;
      notifyListeners();
    }
  }

  void cancel() => _cancellation?.cancel();
}
