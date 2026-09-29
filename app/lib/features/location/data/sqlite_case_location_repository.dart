import 'package:sqflite/sqflite.dart';
import '../../../core/database/database_constants.dart';
import '../../../core/database/iris_database.dart';
import '../domain/case_location.dart';

class SqliteCaseLocationRepository {
  SqliteCaseLocationRepository(this.database);
  final IrisDatabase database;
  Future<CaseLocation?> get(String caseId) async {
    final rows = await (await database.open()).query(IrisDatabaseConstants.caseLocationsTable, where: 'case_id = ?', whereArgs: [caseId], limit: 1);
    return rows.isEmpty ? null : _fromRow(rows.single);
  }
  Future<void> save(CaseLocation location) async {
    final now = location.updatedAt.millisecondsSinceEpoch;
    await (await database.open()).insert(IrisDatabaseConstants.caseLocationsTable, {'case_id': location.caseId, 'latitude': location.latitude, 'longitude': location.longitude, 'source': location.source.storageValue, 'source_evidence_id': location.sourceEvidenceId, 'place_label': location.placeLabel, 'created_at': now, 'updated_at': now}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  CaseLocation _fromRow(Map<String, Object?> row) => CaseLocation(caseId: row['case_id']! as String, latitude: (row['latitude']! as num).toDouble(), longitude: (row['longitude']! as num).toDouble(), source: CaseLocationSource.values.firstWhere((s) => s.storageValue == row['source'], orElse: () => CaseLocationSource.mapSelection), sourceEvidenceId: row['source_evidence_id'] as String?, placeLabel: row['place_label'] as String?, updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int));
}
