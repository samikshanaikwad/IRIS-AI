import 'package:flutter/foundation.dart';
import '../../evidence/domain/evidence_image.dart';
import '../domain/evidence_depth.dart';
import '../domain/depth_visualization.dart';
import 'evidence_depth_service.dart';

class EvidenceDepthController extends ChangeNotifier {
  EvidenceDepthController({required this.evidence, required this.operations});
  final EvidenceImage evidence;
  final EvidenceDepthOperations operations;
  EvidenceDepthSnapshot snapshot = const EvidenceDepthSnapshot(DepthState.notAnalyzed);
  bool busy = false;
  EvidenceDepthVisualization? visualization;
  String? visualizationError;
  Future<void> load() async {
    try {
      snapshot = await operations.load(evidence);
      if (snapshot.analysis != null && snapshot.state == DepthState.analyzed) {
        try { visualization = await operations.loadVisualization(snapshot.analysis!); }
        catch (error) { visualization = null; visualizationError = error.toString(); }
      }
    } catch (_) { snapshot = const EvidenceDepthSnapshot(DepthState.unavailable); }
    notifyListeners();
  }
  Future<void> analyze() async {
    if (busy) return;
    busy = true; snapshot = const EvidenceDepthSnapshot(DepthState.analyzing); notifyListeners();
    try {
      snapshot = EvidenceDepthSnapshot(DepthState.analyzed, analysis: await operations.analyze(evidence));
      visualization = await operations.loadVisualization(snapshot.analysis!);
      visualizationError = null;
    }
    catch (error) { snapshot = EvidenceDepthSnapshot(DepthState.failed, message: error.toString()); }
    finally { busy = false; notifyListeners(); }
  }
}
