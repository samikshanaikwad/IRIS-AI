import 'package:flutter/foundation.dart';
import '../../evidence/domain/evidence_image.dart';
import '../domain/evidence_depth.dart';
import 'evidence_depth_service.dart';

class EvidenceDepthController extends ChangeNotifier {
  EvidenceDepthController({required this.evidence, required this.operations});
  final EvidenceImage evidence;
  final EvidenceDepthOperations operations;
  EvidenceDepthSnapshot snapshot = const EvidenceDepthSnapshot(DepthState.notAnalyzed);
  bool busy = false;
  Future<void> load() async {
    try { snapshot = await operations.load(evidence); } catch (_) { snapshot = const EvidenceDepthSnapshot(DepthState.unavailable); }
    notifyListeners();
  }
  Future<void> analyze() async {
    if (busy) return;
    busy = true; snapshot = const EvidenceDepthSnapshot(DepthState.analyzing); notifyListeners();
    try { snapshot = EvidenceDepthSnapshot(DepthState.analyzed, analysis: await operations.analyze(evidence)); }
    catch (error) { snapshot = EvidenceDepthSnapshot(DepthState.failed, message: error.toString()); }
    finally { busy = false; notifyListeners(); }
  }
}
