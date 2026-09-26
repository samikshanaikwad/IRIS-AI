import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_constants.dart';
import '../../../core/database/iris_database.dart';
import '../domain/case_id_generator.dart';
import '../domain/case_repository.dart';
import '../domain/case_status.dart';
import '../domain/case_title_validator.dart';
import '../domain/incident_case.dart';

typedef CaseClock = DateTime Function();
typedef CaseIdFactory = String Function();

class SqliteCaseRepository implements CaseRepository {
  SqliteCaseRepository(
    this._irisDatabase, {
    CaseClock? clock,
    CaseIdFactory? idFactory,
  }) : _clock = clock ?? _utcNow,
       _idFactory = idFactory ?? generateCaseId;

  final IrisDatabase _irisDatabase;
  final CaseClock _clock;
  final CaseIdFactory _idFactory;

  static DateTime _utcNow() => DateTime.now().toUtc();

  @override
  Future<IncidentCase> createCase({required String title}) async {
    final String normalizedTitle = CaseTitleValidator.normalizeAndValidate(
      title,
    );
    final DateTime timestamp = _clock().toUtc();
    final IncidentCase incidentCase = IncidentCase(
      id: _idFactory(),
      title: normalizedTitle,
      status: CaseStatus.draft,
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    final Database database = await _irisDatabase.open();
    await database.insert(
      IrisDatabaseConstants.casesTable,
      _toRecord(incidentCase),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return incidentCase;
  }

  @override
  Future<bool> deleteCase(String id) async {
    final Database database = await _irisDatabase.open();
    final int deleted = await database.delete(
      IrisDatabaseConstants.casesTable,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    return deleted == 1;
  }

  @override
  Future<IncidentCase?> getCaseById(String id) async {
    final Database database = await _irisDatabase.open();
    final List<Map<String, Object?>> records = await database.query(
      IrisDatabaseConstants.casesTable,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (records.isEmpty) {
      return null;
    }
    return _fromRecord(records.single);
  }

  @override
  Future<List<IncidentCase>> getCases({int? limit}) async {
    if (limit != null && limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be greater than zero.');
    }

    final Database database = await _irisDatabase.open();
    final List<Map<String, Object?>> records = await database.query(
      IrisDatabaseConstants.casesTable,
      orderBy: 'updated_at DESC, created_at DESC, id ASC',
      limit: limit,
    );
    return records.map(_fromRecord).toList(growable: false);
  }

  @override
  Future<IncidentCase> renameCase({
    required String id,
    required String title,
  }) async {
    final String normalizedTitle = CaseTitleValidator.normalizeAndValidate(
      title,
    );
    final Database database = await _irisDatabase.open();

    return database.transaction<IncidentCase>((Transaction transaction) async {
      final List<Map<String, Object?>> records = await transaction.query(
        IrisDatabaseConstants.casesTable,
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (records.isEmpty) {
        throw CaseNotFoundException(id);
      }

      final IncidentCase existing = _fromRecord(records.single);
      if (existing.title == normalizedTitle) {
        return existing;
      }

      final DateTime updatedAt = _clock().toUtc();
      final int updated = await transaction.update(
        IrisDatabaseConstants.casesTable,
        <String, Object?>{
          'title': normalizedTitle,
          'updated_at': updatedAt.millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      if (updated != 1) {
        throw CaseNotFoundException(id);
      }

      return IncidentCase(
        id: existing.id,
        title: normalizedTitle,
        status: existing.status,
        createdAt: existing.createdAt,
        updatedAt: updatedAt,
        incidentOccurredAt: existing.incidentOccurredAt,
        notes: existing.notes,
      );
    });
  }

  Map<String, Object?> _toRecord(IncidentCase incidentCase) {
    return <String, Object?>{
      'id': incidentCase.id,
      'title': incidentCase.title,
      'status': incidentCase.status.storageValue,
      'created_at': incidentCase.createdAt.toUtc().millisecondsSinceEpoch,
      'updated_at': incidentCase.updatedAt.toUtc().millisecondsSinceEpoch,
      'incident_occurred_at': incidentCase.incidentOccurredAt
          ?.toUtc()
          .millisecondsSinceEpoch,
      'notes': incidentCase.notes,
    };
  }

  IncidentCase _fromRecord(Map<String, Object?> record) {
    final int? incidentOccurredAt = record['incident_occurred_at'] as int?;
    return IncidentCase(
      id: record['id']! as String,
      title: record['title']! as String,
      status: CaseStatus.fromStorage(record['status']! as String),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        record['created_at']! as int,
        isUtc: true,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        record['updated_at']! as int,
        isUtc: true,
      ),
      incidentOccurredAt: incidentOccurredAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              incidentOccurredAt,
              isUtc: true,
            ),
      notes: record['notes'] as String?,
    );
  }
}
