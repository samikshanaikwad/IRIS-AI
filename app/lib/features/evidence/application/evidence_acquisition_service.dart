import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import '../../cases/domain/case_id_generator.dart';
import '../data/evidence_storage.dart';
import '../domain/evidence_image.dart';
import '../domain/evidence_repository.dart';

typedef EvidenceClock = DateTime Function();
typedef EvidenceIdFactory = String Function();

class EvidenceImportCandidate {
  const EvidenceImportCandidate({
    required this.path,
    required this.source,
    this.originalDisplayName,
    this.capturedAt,
    this.mimeType,
  });

  final String path;
  final EvidenceSource source;
  final String? originalDisplayName;
  final DateTime? capturedAt;
  final String? mimeType;
}

enum EvidenceImportStatus { imported, duplicate, failed }

class EvidenceImportResult {
  const EvidenceImportResult._(this.status, {this.evidence});

  const EvidenceImportResult.imported(EvidenceImage evidence)
    : this._(EvidenceImportStatus.imported, evidence: evidence);

  const EvidenceImportResult.duplicate()
    : this._(EvidenceImportStatus.duplicate);

  const EvidenceImportResult.failed() : this._(EvidenceImportStatus.failed);

  final EvidenceImportStatus status;
  final EvidenceImage? evidence;
}

class EvidenceImportSummary {
  const EvidenceImportSummary(this.results);

  final List<EvidenceImportResult> results;

  int get imported => results
      .where(
        (EvidenceImportResult item) =>
            item.status == EvidenceImportStatus.imported,
      )
      .length;
  int get duplicates => results
      .where(
        (EvidenceImportResult item) =>
            item.status == EvidenceImportStatus.duplicate,
      )
      .length;
  int get failed => results
      .where(
        (EvidenceImportResult item) =>
            item.status == EvidenceImportStatus.failed,
      )
      .length;
}

class EvidenceAcquisitionService {
  EvidenceAcquisitionService({
    required EvidenceRepository repository,
    required EvidenceStorage storage,
    EvidenceClock? clock,
    EvidenceIdFactory? idFactory,
  }) : _repository = repository,
       _storage = storage,
       _clock = clock ?? _utcNow,
       _idFactory = idFactory ?? generateCaseId;

  final EvidenceRepository _repository;
  final EvidenceStorage _storage;
  final EvidenceClock _clock;
  final EvidenceIdFactory _idFactory;

  static DateTime _utcNow() => DateTime.now().toUtc();

  Future<EvidenceImportSummary> importAll({
    required String caseId,
    required List<EvidenceImportCandidate> candidates,
  }) async {
    final List<EvidenceImportResult> results = <EvidenceImportResult>[];
    for (final EvidenceImportCandidate candidate in candidates) {
      results.add(await _importOne(caseId: caseId, candidate: candidate));
    }
    return EvidenceImportSummary(
      List<EvidenceImportResult>.unmodifiable(results),
    );
  }

  Future<EvidenceImportResult> _importOne({
    required String caseId,
    required EvidenceImportCandidate candidate,
  }) async {
    final String evidenceId = _idFactory();
    final String relativePath = _storage.relativeEvidencePath(
      caseId: caseId,
      evidenceId: evidenceId,
      sourcePath: candidate.path,
    );
    try {
      final File stored = await _storage.copyOriginal(
        sourcePath: candidate.path,
        relativePath: relativePath,
      );
      final String digest = (await sha256.bind(stored.openRead()).first)
          .toString();
      final EvidenceImage? duplicate = await _repository.findDuplicate(
        caseId: caseId,
        sha256: digest,
      );
      if (duplicate != null) {
        await _storage.deleteRelative(relativePath);
        return const EvidenceImportResult.duplicate();
      }

      final ({int width, int height})? dimensions = await _readDimensions(
        stored,
      );
      final EvidenceImage evidence = EvidenceImage(
        id: evidenceId,
        caseId: caseId,
        storedRelativePath: relativePath,
        originalDisplayName:
            candidate.originalDisplayName ?? path.basename(candidate.path),
        source: candidate.source,
        capturedAt: candidate.capturedAt?.toUtc(),
        importedAt: _clock().toUtc(),
        mimeType: candidate.mimeType ?? _mimeType(stored.path),
        widthPx: dimensions?.width,
        heightPx: dimensions?.height,
        fileSizeBytes: await stored.length(),
        sha256: digest,
      );
      try {
        return EvidenceImportResult.imported(await _repository.add(evidence));
      } on DuplicateEvidenceException {
        await _storage.deleteRelative(relativePath);
        return const EvidenceImportResult.duplicate();
      } on Object {
        await _storage.deleteRelative(relativePath);
        rethrow;
      }
    } on Object catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('IRIS evidence import failed (${error.runtimeType}).');
        debugPrint(stackTrace.toString());
      }
      return const EvidenceImportResult.failed();
    }
  }

  Future<({int width, int height})?> _readDimensions(File file) async {
    try {
      final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromFilePath(
        file.path,
      );
      final ui.ImageDescriptor descriptor = await ui.ImageDescriptor.encoded(
        buffer,
      );
      final ({int width, int height}) value = (
        width: descriptor.width,
        height: descriptor.height,
      );
      descriptor.dispose();
      buffer.dispose();
      return value;
    } on Object catch (error) {
      if (kDebugMode) {
        debugPrint(
          'IRIS could not read optional image dimensions (${error.runtimeType}).',
        );
      }
      return null;
    }
  }

  String? _mimeType(String filePath) {
    return switch (path.extension(filePath).toLowerCase()) {
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      '.heic' => 'image/heic',
      '.heif' => 'image/heif',
      '.gif' => 'image/gif',
      '.bmp' => 'image/bmp',
      _ => null,
    };
  }
}
