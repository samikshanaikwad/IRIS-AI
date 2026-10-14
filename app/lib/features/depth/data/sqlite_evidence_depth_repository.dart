import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import '../../../core/database/database_constants.dart';
import '../../../core/database/iris_database.dart';
import '../domain/evidence_depth.dart';
import '../../evidence/domain/image_coordinate_contract.dart';

class SqliteEvidenceDepthRepository {
  SqliteEvidenceDepthRepository(this.database);
  final IrisDatabase database;
  Future<EvidenceDepthAnalysis?> get(String id) async {
    final db = await database.open();
    final rows = await db.query(
      IrisDatabaseConstants.evidenceDepthAnalysesTable,
      where: 'evidence_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _from(rows.single);
  }

  Future<void> save(EvidenceDepthAnalysis v) async {
    final db = await database.open();
    await db.insert(
      IrisDatabaseConstants.evidenceDepthAnalysesTable,
      _to(v),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Map<String, Object?> _to(EvidenceDepthAnalysis v) => {
    'evidence_id': v.evidenceId,
    'model_id': 'depth-anything-v2-small-relative',
    'artifact_sha256': v.artifactSha256,
    'contract_version': 'v1',
    'source_evidence_sha256': v.evidenceSha256,
    'analyzed_at': v.analyzedAt.toUtc().millisecondsSinceEpoch,
    'status': 'complete',
    'input_width': v.width,
    'input_height': v.height,
    'output_width': v.depthWidth,
    'output_height': v.depthHeight,
    'depth_min': v.min,
    'depth_max': v.max,
    'depth_mean': v.mean,
    'depth_file_relative_path': v.depthPath,
    'inference_ms': v.inferenceMs,
    'coordinate_contract_version': v.coordinateMetadata?.contractVersion,
    'coordinate_metadata_json': v.coordinateMetadata == null
        ? null
        : jsonEncode(v.coordinateMetadata!.toJson()),
  };
  EvidenceDepthAnalysis _from(Map<String, Object?> r) => EvidenceDepthAnalysis(
    evidenceId: r['evidence_id']! as String,
    evidenceSha256: r['source_evidence_sha256']! as String,
    artifactSha256: r['artifact_sha256']! as String,
    analyzedAt: DateTime.fromMillisecondsSinceEpoch(
      r['analyzed_at']! as int,
      isUtc: true,
    ),
    width: r['input_width']! as int,
    height: r['input_height']! as int,
    depthWidth: r['output_width']! as int,
    depthHeight: r['output_height']! as int,
    depthPath: r['depth_file_relative_path']! as String,
    min: (r['depth_min']! as num).toDouble(),
    max: (r['depth_max']! as num).toDouble(),
    mean: (r['depth_mean']! as num).toDouble(),
    inferenceMs: r['inference_ms'] as int?,
    coordinateMetadata: _metadata(r['coordinate_metadata_json']),
  );

  ImageCoordinateMetadata? _metadata(Object? encoded) {
    if (encoded is! String || encoded.isEmpty) return null;
    return ImageCoordinateMetadata.fromJson(
      Map<String, Object?>.from(jsonDecode(encoded) as Map),
    );
  }
}
