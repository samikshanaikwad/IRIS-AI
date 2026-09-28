import 'package:sqflite/sqflite.dart';
import '../../../core/database/database_constants.dart';
import '../../../core/database/iris_database.dart';

class GeometryRecord {
  const GeometryRecord({required this.evidenceId, required this.depthSha256, required this.depthAnalyzedAt, required this.algorithmVersion, required this.coordinateVersion, required this.pointCount, required this.path, required this.sha256, required this.analyzedAt});
  final String evidenceId, depthSha256, algorithmVersion, coordinateVersion, path, sha256;
  final DateTime depthAnalyzedAt, analyzedAt;
  final int pointCount;
}

class SqliteGeometryRepository {
  SqliteGeometryRepository(this.database);
  final IrisDatabase database;
  Future<GeometryRecord?> get(String id) async {
    final rows = await (await database.open()).query(IrisDatabaseConstants.evidenceGeometryAnalysesTable, where: 'evidence_id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : _from(rows.single);
  }
  Future<void> save(GeometryRecord r) async => (await database.open()).insert(IrisDatabaseConstants.evidenceGeometryAnalysesTable, {'evidence_id': r.evidenceId, 'depth_evidence_sha256': r.depthSha256, 'depth_analyzed_at': r.depthAnalyzedAt.millisecondsSinceEpoch, 'algorithm_version': r.algorithmVersion, 'coordinate_version': r.coordinateVersion, 'projection_mode': 'normalized_uncalibrated', 'scale_status': 'unresolved', 'point_count': r.pointCount, 'geometry_file_relative_path': r.path, 'geometry_sha256': r.sha256, 'analyzed_at': r.analyzedAt.millisecondsSinceEpoch}, conflictAlgorithm: ConflictAlgorithm.replace);
  GeometryRecord _from(Map<String, Object?> r) => GeometryRecord(evidenceId: r['evidence_id']! as String, depthSha256: r['depth_evidence_sha256']! as String, depthAnalyzedAt: DateTime.fromMillisecondsSinceEpoch(r['depth_analyzed_at']! as int, isUtc: true), algorithmVersion: r['algorithm_version']! as String, coordinateVersion: r['coordinate_version']! as String, pointCount: r['point_count']! as int, path: r['geometry_file_relative_path']! as String, sha256: r['geometry_sha256']! as String, analyzedAt: DateTime.fromMillisecondsSinceEpoch(r['analyzed_at']! as int, isUtc: true));
}
