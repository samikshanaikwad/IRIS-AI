import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../../core/database/database_constants.dart';
import '../../../core/database/iris_database.dart';
import '../domain/case_location.dart';
import '../domain/road_context.dart';
import '../domain/environment_context.dart';

class SqliteCaseLocationRepository {
  SqliteCaseLocationRepository(this.database);
  final IrisDatabase database;
  Future<CaseLocation?> get(String caseId) async {
    final rows = await (await database.open()).query(
      IrisDatabaseConstants.caseLocationsTable,
      where: 'case_id = ?',
      whereArgs: [caseId],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  Future<void> save(CaseLocation location) async {
    final now = location.updatedAt.millisecondsSinceEpoch;
    await (await database.open()).insert(
      IrisDatabaseConstants.caseLocationsTable,
      {
        'case_id': location.caseId,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'source': location.source.storageValue,
        'source_evidence_id': location.sourceEvidenceId,
        'place_label': location.placeLabel,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  CaseLocation _fromRow(Map<String, Object?> row) => CaseLocation(
    caseId: row['case_id']! as String,
    latitude: (row['latitude']! as num).toDouble(),
    longitude: (row['longitude']! as num).toDouble(),
    source: CaseLocationSource.values.firstWhere(
      (s) => s.storageValue == row['source'],
      orElse: () => CaseLocationSource.mapSelection,
    ),
    sourceEvidenceId: row['source_evidence_id'] as String?,
    placeLabel: row['place_label'] as String?,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
  );
  Future<RoadContext?> getRoadContext(String caseId) async {
    final rows = await (await database.open()).query(
      IrisDatabaseConstants.roadContextsTable,
      where: 'case_id = ?',
      whereArgs: [caseId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final raw = jsonDecode(row['roads_json']! as String) as List;
    return RoadContext(
      caseId: caseId,
      latitude: (row['latitude']! as num).toDouble(),
      longitude: (row['longitude']! as num).toDouble(),
      status: row['status']! as String,
      retrievedAt: DateTime.fromMillisecondsSinceEpoch(
        row['retrieved_at']! as int,
      ),
      roads: raw
          .map((r) => RoadSegment.fromJson(r as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<void> saveRoadContext(RoadContext context) async {
    await (await database.open()).insert(
      IrisDatabaseConstants.roadContextsTable,
      {
        'case_id': context.caseId,
        'latitude': context.latitude,
        'longitude': context.longitude,
        'provider': context.provider,
        'retrieved_at': context.retrievedAt.millisecondsSinceEpoch,
        'status': context.status,
        'roads_json': context.json,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<EnvironmentContext?> getEnvironmentContext(String caseId) async {
    final rows = await (await database.open()).query(
      IrisDatabaseConstants.environmentContextsTable,
      where: 'case_id = ?',
      whereArgs: [caseId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final raw = jsonDecode(row['features_json']! as String) as List;
    return EnvironmentContext(
      caseId: caseId,
      latitude: (row['latitude']! as num).toDouble(),
      longitude: (row['longitude']! as num).toDouble(),
      status: row['status']! as String,
      providerState: EnvironmentProviderState.fromStorage(
        row['provider_state'] as String?,
      ),
      retrievedAt: DateTime.fromMillisecondsSinceEpoch(
        row['retrieved_at']! as int,
      ),
      features: raw
          .map((v) => EnvironmentFeature.fromJson(v as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<void> saveEnvironmentContext(EnvironmentContext context) async {
    await (await database.open()).insert(
      IrisDatabaseConstants.environmentContextsTable,
      {
        'case_id': context.caseId,
        'latitude': context.latitude,
        'longitude': context.longitude,
        'provider': context.provider,
        'retrieved_at': context.retrievedAt.millisecondsSinceEpoch,
        'status': context.status,
        'provider_state': context.providerState.storageValue,
        'features_json': context.json,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
