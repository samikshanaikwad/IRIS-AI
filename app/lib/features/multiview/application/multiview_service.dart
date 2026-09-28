import 'package:flutter/services.dart';
import '../../evidence/data/evidence_storage.dart';
import '../../evidence/domain/evidence_image.dart';
import '../data/sqlite_multiview_repository.dart';
import '../domain/multiview_pair_analysis.dart';

class MultiViewService {
  MultiViewService({required this.repository, required this.storage}) : _channel = const MethodChannel('com.iris.multiview/v1');
  final SqliteMultiViewRepository repository;
  final EvidenceStorage storage;
  final MethodChannel _channel;
  Future<MultiViewPairAnalysis> analyze({required String caseId, required EvidenceImage a, required EvidenceImage b}) async {
    if (a.id == b.id) throw ArgumentError('An evidence image cannot be paired with itself.');
    final first = a.id.compareTo(b.id) < 0 ? a : b;
    final second = first.id == a.id ? b : a;
    final raw = Map<String, dynamic>.from(await _channel.invokeMethod<Map<Object?, Object?>>('analyzePair', {'pathA': await storage.absolutePath(first.storedRelativePath), 'pathB': await storage.absolutePath(second.storedRelativePath)}) ?? <Object?, Object?>{});
    final status = _status(raw['status'] as String? ?? 'ERROR');
    final result = MultiViewPairAnalysis(id: canonicalPairId(first.id, second.id), caseId: caseId, evidenceAId: first.id, evidenceBId: second.id, evidenceASha256: first.sha256, evidenceBSha256: second.sha256, featureCountA: raw['featureCountA'] as int? ?? 0, featureCountB: raw['featureCountB'] as int? ?? 0, candidateMatchCount: raw['candidateMatchCount'] as int? ?? 0, acceptedMatchCount: raw['acceptedMatchCount'] as int? ?? 0, verifiedInlierCount: raw['verifiedInlierCount'] as int? ?? 0, inlierRatio: (raw['inlierRatio'] as num? ?? 0).toDouble(), status: status, correspondences: ((raw['correspondences'] as List?) ?? const []).map((e) => (e as List).map((v) => (v as num).toDouble()).toList()).toList(), analyzedAt: DateTime.now(), message: raw['message'] as String?, imageWidthA: raw['imageWidthA'] as int? ?? 640, imageHeightA: raw['imageHeightA'] as int? ?? 640, imageWidthB: raw['imageWidthB'] as int? ?? 640, imageHeightB: raw['imageHeightB'] as int? ?? 640);
    await repository.save(result);
    return result;
  }
  MultiViewStatus _status(String s) {
    final normalized = s.toUpperCase().replaceAll('_', '');
    return MultiViewStatus.values.firstWhere(
      (v) => v.name.toUpperCase() == normalized,
      orElse: () => MultiViewStatus.error,
    );
  }
}
