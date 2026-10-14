import 'dart:convert';

import '../../../core/database/database_constants.dart';
import '../../../core/database/iris_database.dart';
import '../domain/evidence_detection.dart';
import '../../evidence/domain/image_coordinate_contract.dart';

class SqliteEvidenceDetectionRepository {
  SqliteEvidenceDetectionRepository(this._database);
  final IrisDatabase _database;

  Future<EvidenceDetectionAnalysis?> get(String evidenceId) async {
    final db = await _database.open();
    final rows = await db.query(
      IrisDatabaseConstants.evidenceDetectionAnalysesTable,
      where: 'evidence_id = ?',
      whereArgs: [evidenceId],
      orderBy: 'analyzed_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final detections = await db.query(
      IrisDatabaseConstants.evidenceDetectionsTable,
      where: 'analysis_id = ?',
      whereArgs: [row['id']],
      orderBy: 'detection_index',
    );
    return EvidenceDetectionAnalysis(
      id: row['id']! as String,
      evidenceId: row['evidence_id']! as String,
      evidenceSha256: row['evidence_sha256']! as String,
      detectorSha256: row['detector_sha256']! as String,
      thresholdPolicyVersion: row['contract_version']! as String,
      analyzedAt: DateTime.fromMillisecondsSinceEpoch(
        row['analyzed_at']! as int,
        isUtc: true,
      ),
      inferenceMs: row['inference_ms'] as int?,
      coordinateMetadata: _metadata(row['coordinate_metadata_json']),
      detections: detections
          .map(
            (d) => EvidenceDetection(
              classId: d['class_id']! as int,
              className: d['class_name']! as String,
              score: (d['detection_score']! as num).toDouble(),
              ymin: (d['ymin']! as num).toDouble(),
              xmin: (d['xmin']! as num).toDouble(),
              ymax: (d['ymax']! as num).toDouble(),
              xmax: (d['xmax']! as num).toDouble(),
            ),
          )
          .toList(),
    );
  }

  Future<void> save(EvidenceDetectionAnalysis value) async {
    final db = await _database.open();
    await db.transaction((txn) async {
      await txn.delete(
        IrisDatabaseConstants.evidenceDetectionAnalysesTable,
        where: 'evidence_id = ?',
        whereArgs: [value.evidenceId],
      );
      await txn.insert(IrisDatabaseConstants.evidenceDetectionAnalysesTable, {
        'id': value.id,
        'evidence_id': value.evidenceId,
        'evidence_sha256': value.evidenceSha256,
        'detector_id': 'google-efficientdet-lite0-coco',
        'detector_sha256': value.detectorSha256,
        'contract_version': value.thresholdPolicyVersion,
        'status': 'complete',
        'analyzed_at': value.analyzedAt.millisecondsSinceEpoch,
        'inference_ms': value.inferenceMs,
        'coordinate_contract_version':
            value.coordinateMetadata?.contractVersion,
        'coordinate_metadata_json': value.coordinateMetadata == null
            ? null
            : jsonEncode(value.coordinateMetadata!.toJson()),
      });
      for (var i = 0; i < value.detections.length; i++) {
        final d = value.detections[i];
        await txn.insert(IrisDatabaseConstants.evidenceDetectionsTable, {
          'id': '${value.id}-$i',
          'analysis_id': value.id,
          'detection_index': i,
          'class_id': d.classId,
          'class_name': d.className,
          'detection_score': d.score,
          'ymin': d.ymin,
          'xmin': d.xmin,
          'ymax': d.ymax,
          'xmax': d.xmax,
        });
      }
    });
  }

  ImageCoordinateMetadata? _metadata(Object? encoded) {
    if (encoded is! String || encoded.isEmpty) return null;
    return ImageCoordinateMetadata.fromJson(
      Map<String, Object?>.from(jsonDecode(encoded) as Map),
    );
  }
}
