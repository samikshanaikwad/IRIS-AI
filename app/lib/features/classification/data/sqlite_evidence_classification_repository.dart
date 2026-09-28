import '../../../core/database/database_constants.dart';
import '../../../core/database/iris_database.dart';
import 'package:sqflite/sqflite.dart';
import '../domain/evidence_classification.dart';
import '../domain/evidence_classification_repository.dart';

class SqliteEvidenceClassificationRepository
    implements EvidenceClassificationRepository {
  SqliteEvidenceClassificationRepository(this._database);
  final IrisDatabase _database;

  @override
  Future<EvidenceClassification?> getForEvidence(String evidenceId) async {
    final rows = await (await _database.open()).query(
      IrisDatabaseConstants.evidenceClassificationTable,
      where: 'evidence_id = ?',
      whereArgs: <Object?>[evidenceId],
    );
    return rows.isEmpty ? null : _fromRecord(rows.single);
  }

  @override
  Future<void> save(EvidenceClassification value) async {
    await (await _database.open()).insert(
      IrisDatabaseConstants.evidenceClassificationTable,
      <String, Object?>{
        'evidence_id': value.evidenceId,
        'evidence_sha256': value.evidenceSha256,
        'model_id': value.modelId,
        'model_tflite_sha256': value.modelTfliteSha256,
        'model_contract_version': value.modelContractVersion,
        'raw_logit': value.rawLogit,
        'model_score': value.modelScore,
        'threshold': value.threshold,
        'classification_label': value.label.storageValue,
        'analyzed_at': value.analyzedAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  EvidenceClassification _fromRecord(Map<String, Object?> row) =>
      EvidenceClassification(
        evidenceId: row['evidence_id']! as String,
        evidenceSha256: row['evidence_sha256']! as String,
        modelId: row['model_id']! as String,
        modelTfliteSha256: row['model_tflite_sha256']! as String,
        modelContractVersion: row['model_contract_version']! as String,
        rawLogit: (row['raw_logit']! as num).toDouble(),
        modelScore: (row['model_score']! as num).toDouble(),
        threshold: (row['threshold']! as num).toDouble(),
        label: EvidenceClassificationLabel.fromStorage(
          row['classification_label']! as String,
        ),
        analyzedAt: DateTime.fromMillisecondsSinceEpoch(
          row['analyzed_at']! as int,
          isUtc: true,
        ),
      );
}
