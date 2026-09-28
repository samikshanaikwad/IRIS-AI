import 'package:flutter/foundation.dart';
import '../../evidence/domain/evidence_image.dart';
import '../data/sqlite_geometry_repository.dart';
import '../domain/relative_geometry.dart';
import 'relative_geometry_service.dart';

class RelativeGeometryController extends ChangeNotifier {
  RelativeGeometryController({required this.evidence, required this.operations});
  final EvidenceImage evidence; final RelativeGeometryOperations operations;
  GeometryRecord? record; RelativeGeometry? geometry; String? error; bool busy = false;
  Future<void> load() async { try { record = await operations.load(evidence); if (record != null) geometry = await operations.read(record!); } catch (e) { error = e.toString(); } notifyListeners(); }
  Future<void> generate() async { if (busy) return; busy = true; error = null; notifyListeners(); try { record = await operations.generate(evidence); geometry = await operations.read(record!); } catch (e) { error = e.toString(); } finally { busy = false; notifyListeners(); } }
}
