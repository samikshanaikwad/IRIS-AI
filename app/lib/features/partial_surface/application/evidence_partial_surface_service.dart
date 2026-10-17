import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../../depth/application/evidence_depth_service.dart';
import '../../depth/domain/evidence_depth.dart';
import '../../evidence/data/evidence_storage.dart';
import '../../evidence/domain/evidence_image.dart';
import '../../evidence/domain/image_coordinate_contract.dart';
import '../../segmentation/application/evidence_segmentation_service.dart';
import '../../segmentation/domain/evidence_segmentation.dart';
import '../data/evidence_partial_surface_storage.dart';
import '../domain/evidence_partial_surface.dart';
import '../domain/evidence_partial_surface_repository.dart';

abstract interface class EvidencePartialSurfaceOperations {
  bool get executionEnabled;
  Future<EvidencePartialSurfaceSnapshot> load(EvidenceImage evidence);
  Future<EvidencePartialSurfaceAnalysis> generate(
    EvidenceImage evidence, {
    EvidencePartialSurfaceCancellation? cancellation,
    void Function()? onStarted,
  });
  Future<EvidencePartialSurfaceMesh> read(EvidencePartialSurfacePart part);
}

abstract interface class EvidencePartialSurfaceRuntime {
  Future<Map<String, Object?>> generate({
    required String sourceAbsolutePath,
    required String depthAbsolutePath,
    required String outputId,
    required ImageCoordinateMetadata depthMetadata,
    required List<Map<String, Object>> masks,
  });
}

class MethodChannelEvidencePartialSurfaceRuntime
    implements EvidencePartialSurfaceRuntime {
  const MethodChannelEvidencePartialSurfaceRuntime();

  static const MethodChannel _channel = MethodChannel(
    'com.iris.partial_surface/v1',
  );

  @override
  Future<Map<String, Object?>> generate({
    required String sourceAbsolutePath,
    required String depthAbsolutePath,
    required String outputId,
    required ImageCoordinateMetadata depthMetadata,
    required List<Map<String, Object>> masks,
  }) async {
    final response = await _channel
        .invokeMapMethod<String, Object?>('generate', {
          'sourceAbsolutePath': sourceAbsolutePath,
          'depthAbsolutePath': depthAbsolutePath,
          'outputId': outputId,
          'coordinateContractVersion': depthMetadata.contractVersion,
          'orientedWidth': depthMetadata.oriented.width,
          'orientedHeight': depthMetadata.oriented.height,
          'depthWidth': depthMetadata.placement.canvas.width,
          'depthHeight': depthMetadata.placement.canvas.height,
          'depthResizedWidth': depthMetadata.placement.resizedWidth,
          'depthResizedHeight': depthMetadata.placement.resizedHeight,
          'depthOffsetX': depthMetadata.placement.offsetX,
          'depthOffsetY': depthMetadata.placement.offsetY,
          'masks': masks,
        });
    if (response == null) {
      throw StateError('The partial-surface runtime returned no result.');
    }
    return response;
  }
}

class EvidencePartialSurfaceCancellation {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class EvidencePartialSurfaceCancelled implements Exception {
  const EvidencePartialSurfaceCancelled();
}

class EvidencePartialSurfaceInsufficient implements Exception {
  const EvidencePartialSurfaceInsufficient(this.message);
  final String message;
}

/// Builds only visible image/mask/depth samples.  It is intentionally disabled
/// wherever the upstream MobileSAM execution gate is disabled.
class EvidencePartialSurfaceService
    implements EvidencePartialSurfaceOperations {
  EvidencePartialSurfaceService({
    required this.repository,
    required this.storage,
    required this.evidenceStorage,
    required this.segmentation,
    required this.depth,
    required EvidencePartialSurfaceRuntime runtime,
    EvidencePartialSurfaceQueue? queue,
  }) : _runtime = runtime,
       _queue = queue ?? EvidencePartialSurfaceQueue.shared;

  final EvidencePartialSurfaceRepository repository;
  final EvidencePartialSurfaceStorage storage;
  final EvidenceStorage evidenceStorage;
  final EvidenceSegmentationOperations segmentation;
  final EvidenceDepthOperations depth;
  final EvidencePartialSurfaceRuntime _runtime;
  final EvidencePartialSurfaceQueue _queue;

  @override
  bool get executionEnabled => segmentation.executionEnabled;

  @override
  Future<EvidencePartialSurfaceSnapshot> load(EvidenceImage evidence) async {
    final saved = await repository.get(evidence.id);
    final segmentationSnapshot = await segmentation.load(evidence);
    if (segmentationSnapshot.state != EvidenceSegmentationState.current ||
        segmentationSnapshot.analysis == null) {
      return EvidencePartialSurfaceSnapshot(
        saved == null
            ? EvidencePartialSurfaceState.missingSegmentation
            : EvidencePartialSurfaceState.stale,
        analysis: saved,
        message: 'A current genuine car or motorcycle mask is required.',
      );
    }
    final depthSnapshot = await depth.load(evidence);
    if (depthSnapshot.state != DepthState.analyzed ||
        depthSnapshot.analysis == null) {
      return EvidencePartialSurfaceSnapshot(
        saved == null
            ? EvidencePartialSurfaceState.missingDepth
            : EvidencePartialSurfaceState.stale,
        analysis: saved,
        message: 'Current relative depth is required for a visible surface.',
      );
    }
    if (saved == null) {
      return const EvidencePartialSurfaceSnapshot(
        EvidencePartialSurfaceState.notGenerated,
      );
    }
    try {
      final segment = segmentationSnapshot.analysis!;
      final depthAnalysis = depthSnapshot.analysis!;
      final sourceHash = await _hashAbsolute(
        await evidenceStorage.absolutePath(evidence.storedRelativePath),
      );
      final depthHash = await _hashAbsolute(
        await evidenceStorage.absolutePath(depthAnalysis.depthPath),
      );
      final segmentationFingerprint = _segmentationFingerprint(segment);
      final valid =
          saved.processingVersion == EvidencePartialSurfaceProcessing.version &&
          saved.evidenceId == evidence.id &&
          saved.caseId == evidence.caseId &&
          saved.sourceEvidenceSha256 == evidence.sha256 &&
          sourceHash == evidence.sha256 &&
          saved.segmentationAnalysisId == segment.id &&
          saved.segmentationFingerprint == segmentationFingerprint &&
          saved.depthEvidenceSha256 == depthAnalysis.evidenceSha256 &&
          saved.depthAnalyzedAt == depthAnalysis.analyzedAt &&
          saved.depthModelSha256 == depthAnalysis.artifactSha256 &&
          saved.depthFileSha256 == depthHash &&
          _sameRasterMetadata(
            saved.coordinateMetadata,
            segment.coordinateMetadata,
          ) &&
          _sameRasterMetadata(
            saved.coordinateMetadata,
            depthAnalysis.coordinateMetadata,
          ) &&
          await _allPartsCurrent(saved, segment);
      if (!valid) {
        return EvidencePartialSurfaceSnapshot(
          EvidencePartialSurfaceState.stale,
          analysis: saved,
          message:
              'Saved partial surface no longer matches current evidence, mask, or depth.',
        );
      }
      return EvidencePartialSurfaceSnapshot(
        EvidencePartialSurfaceState.current,
        analysis: saved,
      );
    } on Object {
      return EvidencePartialSurfaceSnapshot(
        EvidencePartialSurfaceState.stale,
        analysis: saved,
        message: 'Saved partial-surface artifact failed integrity checks.',
      );
    }
  }

  @override
  Future<EvidencePartialSurfaceAnalysis> generate(
    EvidenceImage evidence, {
    EvidencePartialSurfaceCancellation? cancellation,
    void Function()? onStarted,
  }) {
    if (!executionEnabled) {
      throw StateError(
        'Partial-surface generation is disabled while MobileSAM execution is disabled.',
      );
    }
    final token = cancellation ?? EvidencePartialSurfaceCancellation();
    return _queue.enqueue(() async {
      if (token.isCancelled) throw const EvidencePartialSurfaceCancelled();
      onStarted?.call();
      final segmentSnapshot = await segmentation.load(evidence);
      final segment = segmentSnapshot.analysis;
      if (segmentSnapshot.state != EvidenceSegmentationState.current ||
          segment == null) {
        throw const EvidencePartialSurfaceInsufficient(
          'Generate a current qualified vehicle mask first.',
        );
      }
      final depthSnapshot = await depth.load(evidence);
      final depthAnalysis = depthSnapshot.analysis;
      if (depthSnapshot.state != DepthState.analyzed || depthAnalysis == null) {
        throw const EvidencePartialSurfaceInsufficient(
          'Analyze current relative depth first.',
        );
      }
      final depthMetadata = depthAnalysis.coordinateMetadata;
      if (depthMetadata == null ||
          depthMetadata.contractVersion !=
              IrisImageCoordinateContract.version) {
        throw const EvidencePartialSurfaceInsufficient(
          'Current iris-image-coordinate-v2 relative depth is required.',
        );
      }
      if (!_sameRasterMetadata(segment.coordinateMetadata, depthMetadata)) {
        throw const EvidencePartialSurfaceInsufficient(
          'Mask and depth do not share the same oriented evidence raster.',
        );
      }
      final sourcePath = await evidenceStorage.absolutePath(
        evidence.storedRelativePath,
      );
      final sourceHash = await _hashAbsolute(sourcePath);
      if (sourceHash != evidence.sha256 ||
          segment.sourceEvidenceSha256 != evidence.sha256 ||
          depthAnalysis.evidenceSha256 != evidence.sha256) {
        throw StateError('Evidence, mask, or depth provenance is stale.');
      }
      final depthPath = await evidenceStorage.absolutePath(
        depthAnalysis.depthPath,
      );
      final depthHash = await _hashAbsolute(depthPath);
      if (token.isCancelled) throw const EvidencePartialSurfaceCancelled();

      final analysisId =
          '${evidence.id}-${DateTime.now().microsecondsSinceEpoch}';
      final directory = storage.relativeDirectory(
        caseId: evidence.caseId,
        evidenceId: evidence.id,
        analysisId: analysisId,
      );
      final old = await repository.get(evidence.id);
      final temporaryPaths = <String>{};
      try {
        final result = await _runtime.generate(
          sourceAbsolutePath: sourcePath,
          depthAbsolutePath: depthPath,
          outputId: analysisId,
          depthMetadata: depthMetadata,
          masks: <Map<String, Object>>[
            for (final mask in segment.masks)
              <String, Object>{
                'maskId': mask.id,
                'detectionIndex': mask.detectionIndex,
                'classId': mask.classId,
                'className': mask.className,
                'maskAbsolutePath': await evidenceStorage.absolutePath(
                  mask.maskFileRelativePath,
                ),
              },
          ],
        );
        _verifyRuntime(result, depthMetadata);
        if (token.isCancelled) throw const EvidencePartialSurfaceCancelled();
        final rawParts = List<Object?>.from(result['surfaceResults']! as List);
        final parts = <EvidencePartialSurfacePart>[];
        for (final raw in rawParts) {
          final value = Map<String, Object?>.from(raw! as Map);
          if (value['status'] != 'SURFACE_READY') continue;
          final maskId = value['maskId']! as String;
          final mask = segment.masks
              .where((item) => item.id == maskId)
              .singleOrNull;
          if (mask == null) {
            throw StateError('Surface runtime returned an unknown mask.');
          }
          final nativePath = value['meshPath']! as String;
          final nativeHash = value['meshSha256']! as String;
          temporaryPaths.add(nativePath);
          final suffix = parts.length;
          final relativePath = path.join(directory, 'surface-$suffix.ips');
          await storage.copyAtomic(
            sourceAbsolutePath: nativePath,
            destinationRelativePath: relativePath,
            expectedSha256: nativeHash,
          );
          final part = EvidencePartialSurfacePart(
            id: '$analysisId-$suffix',
            segmentationMaskId: mask.id,
            detectionIndex: mask.detectionIndex,
            classId: mask.classId,
            className: mask.className,
            maskSha256: mask.maskSha256,
            meshFileRelativePath: relativePath,
            meshSha256: nativeHash,
            vertexCount: (value['vertexCount']! as num).toInt(),
            triangleCount: (value['triangleCount']! as num).toInt(),
          );
          // Validate the bounded binary contract before creating a database
          // record. A native/runtime failure must not leave a valid-looking
          // persisted reconstruction behind.
          await storage.read(part);
          parts.add(part);
        }
        if (parts.isEmpty) {
          throw const EvidencePartialSurfaceInsufficient(
            'No valid connected visible surface could be formed from the current mask and depth.',
          );
        }
        final analysis = EvidencePartialSurfaceAnalysis(
          id: analysisId,
          evidenceId: evidence.id,
          caseId: evidence.caseId,
          sourceEvidenceSha256: sourceHash,
          segmentationAnalysisId: segment.id,
          segmentationFingerprint: _segmentationFingerprint(segment),
          depthEvidenceSha256: depthAnalysis.evidenceSha256,
          depthAnalyzedAt: depthAnalysis.analyzedAt,
          depthModelSha256: depthAnalysis.artifactSha256,
          depthFileSha256: depthHash,
          coordinateMetadata: depthMetadata,
          processingVersion: EvidencePartialSurfaceProcessing.version,
          generatedAt: DateTime.now().toUtc(),
          parts: List<EvidencePartialSurfacePart>.unmodifiable(parts),
          totalMs: (result['totalMs'] as num?)?.toDouble(),
          sampledPeakPssKb: (result['sampledPeakPssKb'] as num?)?.toInt(),
          baselinePssKb: (result['baselinePssKb'] as num?)?.toInt(),
        );
        await repository.save(analysis);
        if (old != null) {
          try {
            await storage.deleteDirectory(
              path.dirname(old.parts.first.meshFileRelativePath),
            );
          } on Object {
            // The new verified analysis remains valid if orphan cleanup fails.
          }
        }
        return analysis;
      } on Object {
        await storage.deleteDirectory(directory);
        rethrow;
      } finally {
        for (final nativePath in temporaryPaths) {
          try {
            final file = File(nativePath);
            if (await file.exists()) await file.delete();
          } on Object {
            // Cache cleanup must not turn a verified stored artifact into failure.
          }
        }
      }
    });
  }

  @override
  Future<EvidencePartialSurfaceMesh> read(EvidencePartialSurfacePart part) =>
      storage.read(part);

  Future<bool> _allPartsCurrent(
    EvidencePartialSurfaceAnalysis analysis,
    EvidenceSegmentationAnalysis segmentationAnalysis,
  ) async {
    if (analysis.parts.isEmpty) return false;
    for (final part in analysis.parts) {
      final masks = segmentationAnalysis.masks.where(
        (mask) =>
            mask.id == part.segmentationMaskId &&
            mask.detectionIndex == part.detectionIndex &&
            mask.classId == part.classId &&
            mask.className == part.className &&
            mask.maskSha256 == part.maskSha256,
      );
      if (masks.length != 1 ||
          !await storage.matches(part.meshFileRelativePath, part.meshSha256)) {
        return false;
      }
      await storage.read(part);
    }
    return true;
  }

  String _segmentationFingerprint(EvidenceSegmentationAnalysis analysis) =>
      sha256
          .convert(
            utf8.encode(
              jsonEncode(<String, Object?>{
                'id': analysis.id,
                'source': analysis.sourceEvidenceSha256,
                'model': <String>[
                  analysis.modelId,
                  analysis.modelCheckpointSha256,
                  analysis.encoderSha256,
                  analysis.decoderSha256,
                ],
                'masks': analysis.masks
                    .map(
                      (mask) => <Object>[
                        mask.id,
                        mask.detectionIndex,
                        mask.classId,
                        mask.className,
                        mask.maskSha256,
                      ],
                    )
                    .toList(growable: false),
              }),
            ),
          )
          .toString();

  bool _sameRasterMetadata(
    ImageCoordinateMetadata? left,
    ImageCoordinateMetadata? right,
  ) =>
      left != null &&
      right != null &&
      left.contractVersion == IrisImageCoordinateContract.version &&
      right.contractVersion == IrisImageCoordinateContract.version &&
      left.raw.width == right.raw.width &&
      left.raw.height == right.raw.height &&
      left.orientation == right.orientation &&
      left.oriented.width == right.oriented.width &&
      left.oriented.height == right.oriented.height;

  Future<String> _hashAbsolute(String absolutePath) async {
    final file = File(absolutePath);
    if (!await file.exists()) {
      throw const FileSystemException('Artifact is unavailable.');
    }
    return (await sha256.bind(file.openRead()).first).toString();
  }

  void _verifyRuntime(
    Map<String, Object?> result,
    ImageCoordinateMetadata metadata,
  ) {
    final parts = result['surfaceResults'];
    if (result['status'] != 'PARTIAL_SURFACES_GENERATED_ON_DEVICE' ||
        result['processingVersion'] !=
            EvidencePartialSurfaceProcessing.version ||
        result['coordinateContractVersion'] != metadata.contractVersion ||
        parts is! List) {
      throw StateError('Partial-surface runtime provenance mismatch.');
    }
    for (final raw in parts) {
      if (raw is! Map) throw StateError('Malformed partial-surface result.');
      final value = Map<Object?, Object?>.from(raw);
      if (value['status'] == 'SURFACE_READY') {
        final vertices = (value['vertexCount'] as num?)?.toInt();
        final triangles = (value['triangleCount'] as num?)?.toInt();
        if (value['maskId'] is! String ||
            value['meshPath'] is! String ||
            value['meshSha256'] is! String ||
            !RegExp(
              r'^[0-9a-f]{64}$',
            ).hasMatch(value['meshSha256']! as String) ||
            vertices == null ||
            triangles == null ||
            vertices < 3 ||
            vertices > EvidencePartialSurfaceProcessing.maxVerticesPerPart ||
            triangles < 1 ||
            triangles > EvidencePartialSurfaceProcessing.maxTrianglesPerPart) {
          throw StateError('Partial-surface runtime output is invalid.');
        }
      }
    }
  }
}

class EvidencePartialSurfaceQueue {
  EvidencePartialSurfaceQueue();
  static final EvidencePartialSurfaceQueue shared =
      EvidencePartialSurfaceQueue();
  Future<void> _tail = Future<void>.value();

  Future<T> enqueue<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await operation());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}
