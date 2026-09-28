import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../../core/database/database_constants.dart';
import '../../../core/database/iris_database.dart';
import '../domain/multiview_pair_analysis.dart';

class SqliteMultiViewRepository {
  SqliteMultiViewRepository(this.database);
  final IrisDatabase database;
  Future<void> save(MultiViewPairAnalysis a) async {
    await (await database.open()).insert(IrisDatabaseConstants.multiViewPairAnalysesTable, {
      'id': a.id, 'case_id': a.caseId, 'evidence_a_id': a.evidenceAId, 'evidence_b_id': a.evidenceBId,
      'evidence_a_sha256': a.evidenceASha256, 'evidence_b_sha256': a.evidenceBSha256,
      'algorithm_version': 'orb-fundamental-v1', 'orb_policy': 'ORB(800)',
      'matching_policy': 'BF-Hamming-KNN-ratio-0.75', 'geometric_policy': 'Fundamental-RANSAC-3px-0.99',
      'feature_count_a': a.featureCountA, 'feature_count_b': a.featureCountB,
      'candidate_match_count': a.candidateMatchCount, 'accepted_match_count': a.acceptedMatchCount,
      'verified_inlier_count': a.verifiedInlierCount, 'inlier_ratio': a.inlierRatio,
      'geometric_model': 'fundamental_matrix_ransac', 'status': _storageStatus(a.status),
      'correspondence_json': jsonEncode(a.correspondences), 'analyzed_at': a.analyzedAt.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  String _storageStatus(MultiViewStatus s) {
    switch (s) {
      case MultiViewStatus.verifiedCorrespondence:
        return 'VERIFIED_CORRESPONDENCE';
      case MultiViewStatus.insufficientFeatures:
        return 'INSUFFICIENT_FEATURES';
      case MultiViewStatus.insufficientMatches:
        return 'INSUFFICIENT_MATCHES';
      case MultiViewStatus.geometricVerificationFailed:
        return 'GEOMETRIC_VERIFICATION_FAILED';
      case MultiViewStatus.error:
        return 'ERROR';
    }
  }
}
