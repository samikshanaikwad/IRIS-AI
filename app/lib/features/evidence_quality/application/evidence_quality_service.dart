import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../evidence/data/evidence_storage.dart';
import '../../evidence/domain/evidence_image.dart';
import '../domain/evidence_quality_assessment.dart';
import '../domain/evidence_quality_repository.dart';
import '../processing/image_quality_analyzer.dart';

abstract interface class EvidenceQualityOperations {
  Future<EvidenceQualitySnapshot> load(EvidenceImage evidence);

  Future<EvidenceQualityAssessment> assess(EvidenceImage evidence);
}

class EvidenceQualityService implements EvidenceQualityOperations {
  EvidenceQualityService({
    required EvidenceQualityRepository repository,
    required EvidenceStorage storage,
    required EvidenceQualityAnalyzer analyzer,
  }) : _repository = repository,
       _storage = storage,
       _analyzer = analyzer;

  final EvidenceQualityRepository _repository;
  final EvidenceStorage _storage;
  final EvidenceQualityAnalyzer _analyzer;

  @override
  Future<EvidenceQualitySnapshot> load(EvidenceImage evidence) async {
    final EvidenceQualityAssessment? assessment = await _repository
        .getForEvidence(evidence.id);
    if (assessment == null) {
      return const EvidenceQualitySnapshot.notAssessed();
    }
    if (assessment.algorithmVersion !=
            FlutterImageQualityAnalyzer.algorithmVersion ||
        assessment.expectedSha256 != evidence.sha256) {
      return EvidenceQualitySnapshot.stale(assessment);
    }

    final String absolutePath = await _storage.absolutePath(
      evidence.storedRelativePath,
    );
    final File file = File(absolutePath);
    if (assessment.assessedSha256 == null) {
      try {
        final bool exists = await file.exists();
        if (assessment.fileState == EvidenceFileState.missing && !exists) {
          return EvidenceQualitySnapshot.current(assessment);
        }
        if (assessment.fileState == EvidenceFileState.unreadable && exists) {
          try {
            await sha256.bind(file.openRead()).first;
          } on Object {
            return EvidenceQualitySnapshot.current(assessment);
          }
        }
      } on Object {
        if (assessment.fileState == EvidenceFileState.unreadable) {
          return EvidenceQualitySnapshot.current(assessment);
        }
      }
      return EvidenceQualitySnapshot.stale(assessment);
    }

    try {
      if (!await file.exists()) {
        return EvidenceQualitySnapshot.stale(assessment);
      }
      final String currentSha256 = (await sha256.bind(file.openRead()).first)
          .toString();
      return currentSha256 == assessment.assessedSha256
          ? EvidenceQualitySnapshot.current(assessment)
          : EvidenceQualitySnapshot.stale(assessment);
    } on Object {
      return EvidenceQualitySnapshot.stale(assessment);
    }
  }

  @override
  Future<EvidenceQualityAssessment> assess(EvidenceImage evidence) async {
    final String absolutePath = await _storage.absolutePath(
      evidence.storedRelativePath,
    );
    final EvidenceQualityAssessment assessment = await _analyzer.analyze(
      evidence: evidence,
      absolutePath: absolutePath,
    );
    try {
      await _repository.save(assessment);
    } on Object catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'IRIS calculated quality for ${evidence.id} but could not save it '
          '(${error.runtimeType}).',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
      throw EvidenceQualityPersistenceException(error);
    }
    return assessment;
  }
}

class EvidenceQualityPersistenceException implements Exception {
  const EvidenceQualityPersistenceException(this.cause);

  final Object cause;
}
