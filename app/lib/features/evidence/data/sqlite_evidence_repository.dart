import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_constants.dart';
import '../../../core/database/iris_database.dart';
import '../domain/evidence_image.dart';
import '../domain/evidence_repository.dart';

class SqliteEvidenceRepository implements EvidenceRepository {
  SqliteEvidenceRepository(this._irisDatabase);

  final IrisDatabase _irisDatabase;

  @override
  Future<EvidenceImage> add(EvidenceImage evidence) {
    return _run('add evidence', () async {
      final Database database = await _irisDatabase.open();
      try {
        await database.insert(
          IrisDatabaseConstants.evidenceTable,
          _toRecord(evidence),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      } on DatabaseException catch (error) {
        if (error.isUniqueConstraintError()) {
          final EvidenceImage? duplicate = await findDuplicate(
            caseId: evidence.caseId,
            sha256: evidence.sha256,
          );
          if (duplicate != null) {
            throw DuplicateEvidenceException(duplicate.id);
          }
        }
        rethrow;
      }
      return evidence;
    });
  }

  @override
  Future<bool> delete(String id) {
    return _run('delete evidence', () async {
      final Database database = await _irisDatabase.open();
      return await database.delete(
            IrisDatabaseConstants.evidenceTable,
            where: 'id = ?',
            whereArgs: <Object?>[id],
          ) ==
          1;
    });
  }

  @override
  Future<EvidenceImage?> findDuplicate({
    required String caseId,
    required String sha256,
  }) async {
    final Database database = await _irisDatabase.open();
    final List<Map<String, Object?>> rows = await database.query(
      IrisDatabaseConstants.evidenceTable,
      where: 'case_id = ? AND sha256 = ?',
      whereArgs: <Object?>[caseId, sha256],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRecord(rows.single);
  }

  @override
  Future<EvidenceImage?> getById(String id) {
    return _run('read evidence', () async {
      final Database database = await _irisDatabase.open();
      final List<Map<String, Object?>> rows = await database.query(
        IrisDatabaseConstants.evidenceTable,
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      return rows.isEmpty ? null : _fromRecord(rows.single);
    });
  }

  @override
  Future<List<EvidenceImage>> getForCase(String caseId) {
    return _run('list evidence', () async {
      final Database database = await _irisDatabase.open();
      final List<Map<String, Object?>> rows = await database.query(
        IrisDatabaseConstants.evidenceTable,
        where: 'case_id = ?',
        whereArgs: <Object?>[caseId],
        orderBy: 'imported_at ASC, id ASC',
      );
      return rows.map(_fromRecord).toList(growable: false);
    });
  }

  Future<T> _run<T>(String operation, Future<T> Function() action) async {
    try {
      return await action();
    } on Object catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'IRIS evidence repository failed to $operation '
          '(${error.runtimeType}).',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
      rethrow;
    }
  }

  Map<String, Object?> _toRecord(EvidenceImage evidence) => <String, Object?>{
    'id': evidence.id,
    'case_id': evidence.caseId,
    'stored_relative_path': evidence.storedRelativePath,
    'original_display_name': evidence.originalDisplayName,
    'source_type': evidence.source.storageValue,
    'captured_at': evidence.capturedAt?.toUtc().millisecondsSinceEpoch,
    'imported_at': evidence.importedAt.toUtc().millisecondsSinceEpoch,
    'mime_type': evidence.mimeType,
    'width_px': evidence.widthPx,
    'height_px': evidence.heightPx,
    'file_size_bytes': evidence.fileSizeBytes,
    'sha256': evidence.sha256,
  };

  EvidenceImage _fromRecord(Map<String, Object?> row) {
    final int? capturedAt = row['captured_at'] as int?;
    return EvidenceImage(
      id: row['id']! as String,
      caseId: row['case_id']! as String,
      storedRelativePath: row['stored_relative_path']! as String,
      originalDisplayName: row['original_display_name'] as String?,
      source: EvidenceSource.fromStorage(row['source_type']! as String),
      capturedAt: capturedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(capturedAt, isUtc: true),
      importedAt: DateTime.fromMillisecondsSinceEpoch(
        row['imported_at']! as int,
        isUtc: true,
      ),
      mimeType: row['mime_type'] as String?,
      widthPx: row['width_px'] as int?,
      heightPx: row['height_px'] as int?,
      fileSizeBytes: row['file_size_bytes']! as int,
      sha256: row['sha256']! as String,
    );
  }
}
