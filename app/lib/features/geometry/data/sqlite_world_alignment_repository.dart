import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_constants.dart';
import '../../../core/database/iris_database.dart';
import '../domain/evidence_world_alignment.dart';

class SqliteWorldAlignmentRepository {
  SqliteWorldAlignmentRepository(this.database);
  final IrisDatabase database;

  Future<EvidenceWorldAlignment?> get(String evidenceId) async {
    final rows = await (await database.open()).query(
      IrisDatabaseConstants.evidenceWorldAlignmentsTable,
      where: 'evidence_id = ?',
      whereArgs: [evidenceId],
      limit: 1,
    );
    return rows.isEmpty ? null : _from(rows.single);
  }

  Future<void> save(EvidenceWorldAlignment value) async {
    await (await database.open()).insert(
      IrisDatabaseConstants.evidenceWorldAlignmentsTable,
      {
        'evidence_id': value.evidenceId,
        'case_id': value.caseId,
        'translation_x': value.translationX,
        'translation_y': value.translationY,
        'translation_z': value.translationZ,
        'yaw': value.yaw,
        'uniform_scale': value.uniformScale,
        'source': 'USER_SUPPLIED',
        'geometry_sha256': value.geometrySha256,
        'road_context_fingerprint': value.roadContextFingerprint,
        'world_frame_fingerprint': value.worldFrameFingerprint,
        'provenance_version': value.provenanceVersion,
        'created_at': value.createdAt.millisecondsSinceEpoch,
        'updated_at': value.updatedAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  EvidenceWorldAlignment _from(Map<String, Object?> row) =>
      EvidenceWorldAlignment(
        caseId: row['case_id']! as String,
        evidenceId: row['evidence_id']! as String,
        translationX: (row['translation_x']! as num).toDouble(),
        translationY: (row['translation_y']! as num).toDouble(),
        translationZ: (row['translation_z']! as num).toDouble(),
        yaw: (row['yaw']! as num).toDouble(),
        uniformScale: (row['uniform_scale']! as num).toDouble(),
        source: AlignmentSource.userSupplied,
        geometrySha256: row['geometry_sha256']! as String,
        roadContextFingerprint: row['road_context_fingerprint']! as String,
        worldFrameFingerprint: row['world_frame_fingerprint'] as String?,
        provenanceVersion: row['provenance_version'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          row['created_at']! as int,
          isUtc: true,
        ),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          row['updated_at']! as int,
          isUtc: true,
        ),
      );
}
