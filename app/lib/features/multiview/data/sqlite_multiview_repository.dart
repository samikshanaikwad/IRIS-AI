import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../../core/database/database_constants.dart';
import '../../../core/database/iris_database.dart';
import '../domain/multiview_pair_analysis.dart';
import '../../evidence/domain/evidence_image.dart';
import '../../reconstruction/domain/reconstruction_scene.dart';

class SqliteMultiViewRepository {
  SqliteMultiViewRepository(this.database);
  final IrisDatabase database;
  Future<List<RelatedViews>> currentRelatedViews(
    String caseId,
    List<EvidenceImage> images,
  ) async {
    final byId = {for (final image in images) image.id: image};
    final rows = await (await database.open()).query(
      IrisDatabaseConstants.multiViewPairAnalysesTable,
      where: 'case_id = ? AND status = ? AND algorithm_version = ?',
      whereArgs: [caseId, 'VERIFIED_CORRESPONDENCE', 'orb-fundamental-v1'],
    );
    return rows
        .where(
          (r) =>
              byId[r['evidence_a_id']]?.sha256 == r['evidence_a_sha256'] &&
              byId[r['evidence_b_id']]?.sha256 == r['evidence_b_sha256'],
        )
        .map(
          (r) => RelatedViews(
            r['evidence_a_id'] as String,
            r['evidence_b_id'] as String,
            r['verified_inlier_count'] as int,
          ),
        )
        .toList();
  }

  Future<void> save(MultiViewPairAnalysis a) async {
    await (await database.open()).insert(
      IrisDatabaseConstants.multiViewPairAnalysesTable,
      {
        'id': a.id,
        'case_id': a.caseId,
        'evidence_a_id': a.evidenceAId,
        'evidence_b_id': a.evidenceBId,
        'evidence_a_sha256': a.evidenceASha256,
        'evidence_b_sha256': a.evidenceBSha256,
        'algorithm_version': 'orb-fundamental-v1',
        'orb_policy': 'ORB(800)',
        'matching_policy': 'BF-Hamming-KNN-ratio-0.75',
        'geometric_policy': 'Fundamental-RANSAC-3px-0.99',
        'feature_count_a': a.featureCountA,
        'feature_count_b': a.featureCountB,
        'candidate_match_count': a.candidateMatchCount,
        'accepted_match_count': a.acceptedMatchCount,
        'verified_inlier_count': a.verifiedInlierCount,
        'inlier_ratio': a.inlierRatio,
        'geometric_model': 'fundamental_matrix_ransac',
        'status': _storageStatus(a.status),
        'correspondence_json': jsonEncode(a.correspondences),
        'analyzed_at': a.analyzedAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
