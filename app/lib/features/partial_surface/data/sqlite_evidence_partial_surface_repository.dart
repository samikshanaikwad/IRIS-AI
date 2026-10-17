import 'dart:convert';

import '../../../core/database/database_constants.dart';
import '../../../core/database/iris_database.dart';
import '../../evidence/domain/image_coordinate_contract.dart';
import '../domain/evidence_partial_surface.dart';
import '../domain/evidence_partial_surface_repository.dart';

class SqliteEvidencePartialSurfaceRepository
    implements EvidencePartialSurfaceRepository {
  SqliteEvidencePartialSurfaceRepository(this._database);

  final IrisDatabase _database;

  @override
  Future<EvidencePartialSurfaceAnalysis?> get(String evidenceId) async {
    final database = await _database.open();
    final rows = await database.query(
      IrisDatabaseConstants.evidencePartialSurfaceAnalysesTable,
      where: 'evidence_id = ?',
      whereArgs: <Object?>[evidenceId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final parts = await database.query(
      IrisDatabaseConstants.evidencePartialSurfacePartsTable,
      where: 'analysis_id = ?',
      whereArgs: <Object?>[row['id']],
      orderBy: 'detection_index ASC',
    );
    return EvidencePartialSurfaceAnalysis(
      id: row['id']! as String,
      evidenceId: row['evidence_id']! as String,
      caseId: row['case_id']! as String,
      sourceEvidenceSha256: row['source_evidence_sha256']! as String,
      segmentationAnalysisId: row['segmentation_analysis_id']! as String,
      segmentationFingerprint: row['segmentation_fingerprint']! as String,
      depthEvidenceSha256: row['depth_evidence_sha256']! as String,
      depthAnalyzedAt: DateTime.fromMillisecondsSinceEpoch(
        row['depth_analyzed_at']! as int,
        isUtc: true,
      ),
      depthModelSha256: row['depth_model_sha256']! as String,
      depthFileSha256: row['depth_file_sha256']! as String,
      coordinateMetadata: ImageCoordinateMetadata.fromJson(
        Map<String, Object?>.from(
          jsonDecode(row['coordinate_metadata_json']! as String) as Map,
        ),
      ),
      processingVersion: row['processing_version']! as String,
      generatedAt: DateTime.fromMillisecondsSinceEpoch(
        row['generated_at']! as int,
        isUtc: true,
      ),
      totalMs: (row['total_ms'] as num?)?.toDouble(),
      sampledPeakPssKb: row['sampled_peak_pss_kb'] as int?,
      baselinePssKb: row['baseline_pss_kb'] as int?,
      parts: List<EvidencePartialSurfacePart>.unmodifiable(parts.map(_part)),
    );
  }

  @override
  Future<void> save(EvidencePartialSurfaceAnalysis analysis) async {
    if (analysis.parts.isEmpty) {
      throw ArgumentError(
        'A partial surface analysis requires real mesh data.',
      );
    }
    final database = await _database.open();
    await database.transaction((transaction) async {
      await transaction.delete(
        IrisDatabaseConstants.evidencePartialSurfaceAnalysesTable,
        where: 'evidence_id = ?',
        whereArgs: <Object?>[analysis.evidenceId],
      );
      await transaction.insert(
        IrisDatabaseConstants.evidencePartialSurfaceAnalysesTable,
        <String, Object?>{
          'id': analysis.id,
          'evidence_id': analysis.evidenceId,
          'case_id': analysis.caseId,
          'source_evidence_sha256': analysis.sourceEvidenceSha256,
          'segmentation_analysis_id': analysis.segmentationAnalysisId,
          'segmentation_fingerprint': analysis.segmentationFingerprint,
          'depth_evidence_sha256': analysis.depthEvidenceSha256,
          'depth_analyzed_at': analysis.depthAnalyzedAt.millisecondsSinceEpoch,
          'depth_model_sha256': analysis.depthModelSha256,
          'depth_file_sha256': analysis.depthFileSha256,
          'coordinate_contract_version':
              analysis.coordinateMetadata.contractVersion,
          'coordinate_metadata_json': jsonEncode(
            analysis.coordinateMetadata.toJson(),
          ),
          'processing_version': analysis.processingVersion,
          'generated_at': analysis.generatedAt.millisecondsSinceEpoch,
          'total_ms': analysis.totalMs,
          'sampled_peak_pss_kb': analysis.sampledPeakPssKb,
          'baseline_pss_kb': analysis.baselinePssKb,
        },
      );
      for (final part in analysis.parts) {
        await transaction.insert(
          IrisDatabaseConstants.evidencePartialSurfacePartsTable,
          <String, Object?>{
            'id': part.id,
            'analysis_id': analysis.id,
            'segmentation_mask_id': part.segmentationMaskId,
            'detection_index': part.detectionIndex,
            'class_id': part.classId,
            'class_name': part.className,
            'mask_sha256': part.maskSha256,
            'mesh_file_relative_path': part.meshFileRelativePath,
            'mesh_sha256': part.meshSha256,
            'vertex_count': part.vertexCount,
            'triangle_count': part.triangleCount,
          },
        );
      }
    });
  }

  EvidencePartialSurfacePart _part(Map<String, Object?> row) =>
      EvidencePartialSurfacePart(
        id: row['id']! as String,
        segmentationMaskId: row['segmentation_mask_id']! as String,
        detectionIndex: row['detection_index']! as int,
        classId: row['class_id']! as int,
        className: row['class_name']! as String,
        maskSha256: row['mask_sha256']! as String,
        meshFileRelativePath: row['mesh_file_relative_path']! as String,
        meshSha256: row['mesh_sha256']! as String,
        vertexCount: row['vertex_count']! as int,
        triangleCount: row['triangle_count']! as int,
      );
}
