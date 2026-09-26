import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_constants.dart';
import '../../../core/database/iris_database.dart';
import '../domain/evidence_quality_assessment.dart';
import '../domain/evidence_quality_repository.dart';

class SqliteEvidenceQualityRepository implements EvidenceQualityRepository {
  SqliteEvidenceQualityRepository(this._irisDatabase);

  final IrisDatabase _irisDatabase;

  @override
  Future<EvidenceQualityAssessment?> getForEvidence(String evidenceId) {
    return _run('read evidence quality', () async {
      final Database database = await _irisDatabase.open();
      final List<Map<String, Object?>> rows = await database.query(
        IrisDatabaseConstants.evidenceQualityTable,
        where: 'evidence_id = ?',
        whereArgs: <Object?>[evidenceId],
        limit: 1,
      );
      return rows.isEmpty ? null : _fromRecord(rows.single);
    });
  }

  @override
  Future<void> save(EvidenceQualityAssessment assessment) {
    return _run('save evidence quality', () async {
      final Database database = await _irisDatabase.open();
      await database.insert(
        IrisDatabaseConstants.evidenceQualityTable,
        _toRecord(assessment),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<T> _run<T>(String operation, Future<T> Function() action) async {
    try {
      return await action();
    } on Object catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'IRIS quality repository failed to $operation '
          '(${error.runtimeType}).',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
      rethrow;
    }
  }

  Map<String, Object?> _toRecord(EvidenceQualityAssessment assessment) =>
      <String, Object?>{
        'evidence_id': assessment.evidenceId,
        'assessed_at': assessment.assessedAt.toUtc().millisecondsSinceEpoch,
        'algorithm_version': assessment.algorithmVersion,
        'expected_sha256': assessment.expectedSha256,
        'assessed_sha256': assessment.assessedSha256,
        'file_state': assessment.fileState.storageValue,
        'decode_state': assessment.decodeState.storageValue,
        'integrity_state': assessment.integrityState.storageValue,
        'readiness_state': assessment.readiness.storageValue,
        'file_size_bytes': assessment.fileSizeBytes,
        'original_width': assessment.originalWidth,
        'original_height': assessment.originalHeight,
        'analysis_width': assessment.analysisWidth,
        'analysis_height': assessment.analysisHeight,
        'orientation': assessment.orientation?.storageValue,
        'sharpness_value': assessment.sharpnessValue,
        'mean_luminance': assessment.meanLuminance,
        'dark_clipped_fraction': assessment.darkClippedFraction,
        'bright_clipped_fraction': assessment.brightClippedFraction,
        'findings_json': jsonEncode(
          assessment.findings.map(_findingToRecord).toList(growable: false),
        ),
      };

  EvidenceQualityAssessment _fromRecord(Map<String, Object?> row) {
    final Object? decoded = jsonDecode(row['findings_json']! as String);
    if (decoded is! List<Object?>) {
      throw const FormatException('Evidence quality findings are invalid.');
    }
    return EvidenceQualityAssessment(
      evidenceId: row['evidence_id']! as String,
      assessedAt: DateTime.fromMillisecondsSinceEpoch(
        row['assessed_at']! as int,
        isUtc: true,
      ),
      algorithmVersion: row['algorithm_version']! as String,
      expectedSha256: row['expected_sha256']! as String,
      assessedSha256: row['assessed_sha256'] as String?,
      fileState: EvidenceFileState.fromStorage(row['file_state']! as String),
      decodeState: EvidenceDecodeState.fromStorage(
        row['decode_state']! as String,
      ),
      integrityState: EvidenceIntegrityState.fromStorage(
        row['integrity_state']! as String,
      ),
      readiness: EvidenceReadiness.fromStorage(
        row['readiness_state']! as String,
      ),
      fileSizeBytes: row['file_size_bytes'] as int?,
      originalWidth: row['original_width'] as int?,
      originalHeight: row['original_height'] as int?,
      analysisWidth: row['analysis_width'] as int?,
      analysisHeight: row['analysis_height'] as int?,
      orientation: row['orientation'] == null
          ? null
          : EvidenceOrientation.fromStorage(row['orientation']! as String),
      sharpnessValue: (row['sharpness_value'] as num?)?.toDouble(),
      meanLuminance: (row['mean_luminance'] as num?)?.toDouble(),
      darkClippedFraction: (row['dark_clipped_fraction'] as num?)?.toDouble(),
      brightClippedFraction: (row['bright_clipped_fraction'] as num?)
          ?.toDouble(),
      findings: List<EvidenceQualityFinding>.unmodifiable(
        decoded.map((Object? value) {
          if (value is! Map<String, Object?>) {
            throw const FormatException(
              'Evidence quality finding entry is invalid.',
            );
          }
          return _findingFromRecord(value);
        }),
      ),
    );
  }

  Map<String, Object?> _findingToRecord(EvidenceQualityFinding finding) =>
      <String, Object?>{
        'code': finding.code.storageValue,
        'severity': finding.severity.storageValue,
        'metric': finding.metric.storageValue,
        'measured_value': finding.measuredValue,
        'threshold': finding.threshold,
        'unit': finding.unit,
        'explanation': finding.explanation,
      };

  EvidenceQualityFinding _findingFromRecord(Map<String, Object?> record) =>
      EvidenceQualityFinding(
        code: EvidenceQualityFindingCode.fromStorage(record['code']! as String),
        severity: EvidenceQualitySeverity.fromStorage(
          record['severity']! as String,
        ),
        metric: EvidenceQualityMetric.fromStorage(record['metric']! as String),
        measuredValue: (record['measured_value'] as num?)?.toDouble(),
        threshold: (record['threshold'] as num?)?.toDouble(),
        unit: record['unit'] as String?,
        explanation: record['explanation']! as String,
      );
}
