import 'dart:convert';

import '../../../core/database/database_constants.dart';
import '../../../core/database/iris_database.dart';
import '../../evidence/domain/image_coordinate_contract.dart';
import '../domain/evidence_segmentation.dart';
import '../domain/evidence_segmentation_repository.dart';

class SqliteEvidenceSegmentationRepository
    implements EvidenceSegmentationRepository {
  SqliteEvidenceSegmentationRepository(this._database);

  final IrisDatabase _database;

  @override
  Future<EvidenceSegmentationAnalysis?> get(String evidenceId) async {
    final database = await _database.open();
    final rows = await database.query(
      IrisDatabaseConstants.evidenceSegmentationAnalysesTable,
      where: 'evidence_id = ?',
      whereArgs: <Object?>[evidenceId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final maskRows = await database.query(
      IrisDatabaseConstants.evidenceSegmentationMasksTable,
      where: 'analysis_id = ?',
      whereArgs: <Object?>[row['id']],
      orderBy: 'detection_index ASC',
    );
    return EvidenceSegmentationAnalysis(
      id: row['id']! as String,
      evidenceId: row['evidence_id']! as String,
      caseId: row['case_id']! as String,
      sourceEvidenceSha256: row['source_evidence_sha256']! as String,
      detectionAnalysisId: row['detection_analysis_id']! as String,
      detectorSha256: row['detector_sha256']! as String,
      detectorContractVersion: row['detector_contract_version']! as String,
      modelId: row['model_id']! as String,
      modelSourceCommit: row['model_source_commit']! as String,
      modelCheckpointSha256: row['model_checkpoint_sha256']! as String,
      encoderSha256: row['encoder_sha256']! as String,
      decoderSha256: row['decoder_sha256']! as String,
      coordinateMetadata: ImageCoordinateMetadata.fromJson(
        Map<String, Object?>.from(
          jsonDecode(row['coordinate_metadata_json']! as String) as Map,
        ),
      ),
      analyzedAt: DateTime.fromMillisecondsSinceEpoch(
        row['analyzed_at']! as int,
        isUtc: true,
      ),
      overlayFileRelativePath: row['overlay_file_relative_path']! as String,
      overlaySha256: row['overlay_sha256']! as String,
      encoderMs: (row['encoder_ms'] as num?)?.toDouble(),
      decoderMs: (row['decoder_ms'] as num?)?.toDouble(),
      totalMs: (row['total_ms'] as num?)?.toDouble(),
      sampledPeakPssKb: row['sampled_peak_pss_kb'] as int?,
      baselinePssKb: row['baseline_pss_kb'] as int?,
      masks: maskRows
          .map(
            (mask) => EvidenceSegmentationMask(
              id: mask['id']! as String,
              detectionIndex: mask['detection_index']! as int,
              classId: mask['class_id']! as int,
              className: mask['class_name']! as String,
              detectionScore: (mask['detection_score']! as num).toDouble(),
              promptLeft: (mask['prompt_left']! as num).toDouble(),
              promptTop: (mask['prompt_top']! as num).toDouble(),
              promptRight: (mask['prompt_right']! as num).toDouble(),
              promptBottom: (mask['prompt_bottom']! as num).toDouble(),
              maskFileRelativePath: mask['mask_file_relative_path']! as String,
              maskSha256: mask['mask_sha256']! as String,
              maskPixelCount: mask['mask_pixel_count']! as int,
              predictedQuality: (mask['predicted_quality'] as num?)?.toDouble(),
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<void> save(EvidenceSegmentationAnalysis analysis) async {
    if (analysis.masks.isEmpty) {
      throw ArgumentError('A segmentation analysis must contain a real mask.');
    }
    final database = await _database.open();
    await database.transaction((transaction) async {
      await transaction.delete(
        IrisDatabaseConstants.evidenceSegmentationAnalysesTable,
        where: 'evidence_id = ?',
        whereArgs: <Object?>[analysis.evidenceId],
      );
      await transaction.insert(
        IrisDatabaseConstants.evidenceSegmentationAnalysesTable,
        <String, Object?>{
          'id': analysis.id,
          'evidence_id': analysis.evidenceId,
          'case_id': analysis.caseId,
          'source_evidence_sha256': analysis.sourceEvidenceSha256,
          'detection_analysis_id': analysis.detectionAnalysisId,
          'detector_sha256': analysis.detectorSha256,
          'detector_contract_version': analysis.detectorContractVersion,
          'model_id': analysis.modelId,
          'model_source_commit': analysis.modelSourceCommit,
          'model_checkpoint_sha256': analysis.modelCheckpointSha256,
          'encoder_sha256': analysis.encoderSha256,
          'decoder_sha256': analysis.decoderSha256,
          'coordinate_contract_version':
              analysis.coordinateMetadata.contractVersion,
          'coordinate_metadata_json': jsonEncode(
            analysis.coordinateMetadata.toJson(),
          ),
          'analyzed_at': analysis.analyzedAt.millisecondsSinceEpoch,
          'mask_count': analysis.masks.length,
          'overlay_file_relative_path': analysis.overlayFileRelativePath,
          'overlay_sha256': analysis.overlaySha256,
          'encoder_ms': analysis.encoderMs,
          'decoder_ms': analysis.decoderMs,
          'total_ms': analysis.totalMs,
          'sampled_peak_pss_kb': analysis.sampledPeakPssKb,
          'baseline_pss_kb': analysis.baselinePssKb,
        },
      );
      for (final mask in analysis.masks) {
        await transaction.insert(
          IrisDatabaseConstants.evidenceSegmentationMasksTable,
          <String, Object?>{
            'id': mask.id,
            'analysis_id': analysis.id,
            'detection_index': mask.detectionIndex,
            'class_id': mask.classId,
            'class_name': mask.className,
            'detection_score': mask.detectionScore,
            'prompt_left': mask.promptLeft,
            'prompt_top': mask.promptTop,
            'prompt_right': mask.promptRight,
            'prompt_bottom': mask.promptBottom,
            'mask_file_relative_path': mask.maskFileRelativePath,
            'mask_sha256': mask.maskSha256,
            'mask_pixel_count': mask.maskPixelCount,
            'predicted_quality': mask.predictedQuality,
          },
        );
      }
    });
  }
}
