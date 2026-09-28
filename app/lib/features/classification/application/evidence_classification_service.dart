import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../../evidence/data/evidence_storage.dart';
import '../../evidence/domain/evidence_image.dart';
import '../../evidence_quality/application/evidence_quality_service.dart';
import '../../evidence_quality/domain/evidence_quality_assessment.dart';
import '../domain/evidence_classification.dart';
import '../domain/evidence_classification_repository.dart';

abstract interface class EvidenceClassificationOperations {
  Future<EvidenceClassificationSnapshot> load(EvidenceImage evidence);
  Future<EvidenceClassification> analyze(EvidenceImage evidence);
}

class EvidenceClassificationService
    implements EvidenceClassificationOperations {
  EvidenceClassificationService({
    required EvidenceClassificationRepository repository,
    required EvidenceStorage storage,
    required EvidenceQualityOperations quality,
  }) : _repository = repository,
       _storage = storage,
       _quality = quality;
  final EvidenceClassificationRepository _repository;
  final EvidenceStorage _storage;
  final EvidenceQualityOperations _quality;
  static const MethodChannel _channel = MethodChannel('com.iris.classifier/v1');
  static const String modelId =
      'iris-v0-experimental-mobilenet-v3-small-tflite-v1';
  static const String modelSha256 =
      'e98d17518b0296a484a0a94c21359a6703b11b56e5db53a1cc659b8b3a440c96';
  static const String contractVersion =
      'iris-v0-experimental-mobilenet-v3-small-tflite-v1';
  static const double threshold = 0.8611480594;

  @override
  Future<EvidenceClassificationSnapshot> load(EvidenceImage evidence) async {
    final EvidenceQualitySnapshot quality = await _quality.load(evidence);
    if (quality.state == EvidenceQualitySnapshotState.notAssessed ||
        quality.state == EvidenceQualitySnapshotState.stale) {
      return const EvidenceClassificationSnapshot.qualityRequired();
    }
    if (quality.state == EvidenceQualitySnapshotState.unavailable) {
      return const EvidenceClassificationSnapshot.unavailable();
    }
    if (quality.assessment!.readiness == EvidenceReadiness.notUsable) {
      return const EvidenceClassificationSnapshot.blocked();
    }
    final bool qualityHasLimitations =
        quality.assessment!.readiness ==
        EvidenceReadiness.usableWithLimitations;
    final EvidenceClassification? existing = await _repository.getForEvidence(
      evidence.id,
    );
    if (existing == null) {
      return EvidenceClassificationSnapshot.notAnalyzed(
        qualityHasLimitations: qualityHasLimitations,
      );
    }
    final String actualSha = await _managedSha(evidence);
    if (actualSha != evidence.sha256 ||
        existing.evidenceSha256 != actualSha ||
        existing.modelTfliteSha256 != modelSha256 ||
        existing.modelContractVersion != contractVersion) {
      return EvidenceClassificationSnapshot.stale(
        existing,
        qualityHasLimitations: qualityHasLimitations,
      );
    }
    return EvidenceClassificationSnapshot.current(
      existing,
      qualityHasLimitations: qualityHasLimitations,
    );
  }

  @override
  Future<EvidenceClassification> analyze(EvidenceImage evidence) async {
    final EvidenceQualitySnapshot quality = await _quality.load(evidence);
    if (quality.state != EvidenceQualitySnapshotState.current) {
      throw const ClassificationUnavailableException(
        'Quality assessment is required before classification.',
      );
    }
    if (quality.assessment!.readiness == EvidenceReadiness.notUsable) {
      throw const ClassificationUnavailableException(
        'This evidence is not usable for classification.',
      );
    }
    final String path = await _storage.absolutePath(
      evidence.storedRelativePath,
    );
    final String actualSha = await _managedSha(evidence);
    if (actualSha != evidence.sha256) {
      throw const ClassificationIntegrityException();
    }
    final Map<Object?, Object?> response =
        await _channel.invokeMapMethod<Object?, Object?>(
          'run',
          <String, Object?>{'absolutePath': path},
        ) ??
        <Object?, Object?>{};
    if (response['modelSha256'] != modelSha256 ||
        response['rawLogit'] is! num) {
      throw const ClassificationRuntimeException();
    }
    final double rawLogit = (response['rawLogit']! as num).toDouble();
    if (!rawLogit.isFinite) {
      throw const ClassificationRuntimeException();
    }
    final double score = _sigmoid(rawLogit);
    final EvidenceClassification classification = EvidenceClassification(
      evidenceId: evidence.id,
      evidenceSha256: actualSha,
      modelId: modelId,
      modelTfliteSha256: modelSha256,
      modelContractVersion: contractVersion,
      rawLogit: rawLogit,
      modelScore: score,
      threshold: threshold,
      label: score >= threshold
          ? EvidenceClassificationLabel.accident
          : EvidenceClassificationLabel.nonAccident,
      analyzedAt: DateTime.now().toUtc(),
    );
    await _repository.save(classification);
    return classification;
  }

  Future<String> _managedSha(EvidenceImage evidence) async {
    final File file = File(
      await _storage.absolutePath(evidence.storedRelativePath),
    );
    if (!await file.exists()) {
      throw const ClassificationIntegrityException();
    }
    return (await sha256.bind(file.openRead()).first).toString();
  }

  static double _sigmoid(double value) =>
      value >= 0 ? 1 / (1 + exp(-value)) : exp(value) / (1 + exp(value));
}

class ClassificationUnavailableException implements Exception {
  const ClassificationUnavailableException(this.message);
  final String message;
}

class ClassificationIntegrityException implements Exception {
  const ClassificationIntegrityException();
}

class ClassificationRuntimeException implements Exception {
  const ClassificationRuntimeException();
}
