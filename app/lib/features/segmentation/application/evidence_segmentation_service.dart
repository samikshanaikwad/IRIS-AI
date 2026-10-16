import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../../detection/application/evidence_detection_service.dart';
import '../../detection/domain/evidence_detection.dart';
import '../../evidence/data/evidence_storage.dart';
import '../../evidence/domain/evidence_image.dart';
import '../../evidence/domain/image_coordinate_contract.dart';
import '../../segmentation_qualification/segmentation_prompt_box.dart';
import '../data/evidence_segmentation_storage.dart';
import '../domain/evidence_segmentation.dart';
import '../domain/evidence_segmentation_repository.dart';

abstract interface class EvidenceSegmentationOperations {
  bool get executionEnabled;
  Future<EvidenceSegmentationSnapshot> load(EvidenceImage evidence);
  Future<EvidenceSegmentationAnalysis> analyze(
    EvidenceImage evidence, {
    EvidenceSegmentationCancellation? cancellation,
    void Function()? onStarted,
  });
  Future<String> overlayAbsolutePath(EvidenceSegmentationAnalysis analysis);
}

abstract interface class EvidenceSegmentationRuntime {
  Future<Map<String, Object?>> run({
    required String absolutePath,
    required String coordinateContractVersion,
    required String outputId,
    required List<Map<String, Object>> boxes,
  });
}

class MethodChannelEvidenceSegmentationRuntime
    implements EvidenceSegmentationRuntime {
  const MethodChannelEvidenceSegmentationRuntime();

  static const MethodChannel _channel = MethodChannel(
    'com.iris.segmentation/v1',
  );

  @override
  Future<Map<String, Object?>> run({
    required String absolutePath,
    required String coordinateContractVersion,
    required String outputId,
    required List<Map<String, Object>> boxes,
  }) async {
    final response = await _channel
        .invokeMapMethod<String, Object?>('run', <String, Object?>{
          'absolutePath': absolutePath,
          'coordinateContractVersion': coordinateContractVersion,
          'outputId': outputId,
          'boxes': boxes,
        });
    if (response == null) {
      throw StateError('The segmentation runtime returned no result.');
    }
    return response;
  }
}

class EvidenceSegmentationCancellation {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class EvidenceSegmentationCancelled implements Exception {
  const EvidenceSegmentationCancelled();
}

class EvidenceSegmentationUnavailable implements Exception {
  const EvidenceSegmentationUnavailable(this.message);
  final String message;
}

class EvidenceSegmentationUnsupported implements Exception {
  const EvidenceSegmentationUnsupported(this.message);
  final String message;
}

class EvidenceSegmentationRuntimeFailure implements Exception {
  const EvidenceSegmentationRuntimeFailure(this.message);
  final String message;
}

class EvidenceSegmentationService implements EvidenceSegmentationOperations {
  EvidenceSegmentationService({
    required this.repository,
    required this.storage,
    required this.evidenceStorage,
    required this.detection,
    required EvidenceSegmentationRuntime runtime,
    required this.executionEnabled,
    EvidenceSegmentationQueue? queue,
  }) : _runtime = runtime,
       _queue = queue ?? EvidenceSegmentationQueue.shared;

  final EvidenceSegmentationRepository repository;
  final EvidenceSegmentationStorage storage;
  final EvidenceStorage evidenceStorage;
  final EvidenceDetectionOperations detection;
  final EvidenceSegmentationRuntime _runtime;
  final EvidenceSegmentationQueue _queue;

  @override
  final bool executionEnabled;

  @override
  Future<EvidenceSegmentationSnapshot> load(EvidenceImage evidence) async {
    final saved = await repository.get(evidence.id);
    if (saved == null) {
      return const EvidenceSegmentationSnapshot(
        EvidenceSegmentationState.notAnalyzed,
      );
    }
    if (await _sourceHash(evidence) != evidence.sha256 ||
        saved.sourceEvidenceSha256 != evidence.sha256 ||
        saved.evidenceId != evidence.id ||
        saved.caseId != evidence.caseId ||
        !isCurrentSegmentationModel(saved)) {
      return EvidenceSegmentationSnapshot(
        EvidenceSegmentationState.stale,
        analysis: saved,
        message: 'Saved masks no longer match the evidence or model.',
      );
    }
    final detectionSnapshot = await detection.load(evidence);
    final currentDetection = detectionSnapshot.analysis;
    if (detectionSnapshot.state != DetectionState.complete ||
        currentDetection == null ||
        currentDetection.id != saved.detectionAnalysisId ||
        currentDetection.detectorSha256 != saved.detectorSha256 ||
        currentDetection.thresholdPolicyVersion !=
            saved.detectorContractVersion ||
        !_sameCoordinateMetadata(
          currentDetection.coordinateMetadata,
          saved.coordinateMetadata,
        )) {
      return EvidenceSegmentationSnapshot(
        EvidenceSegmentationState.stale,
        analysis: saved,
        message: 'Saved masks no longer match current TASK007 detections.',
      );
    }
    if (!await storage.matches(
          saved.overlayFileRelativePath,
          saved.overlaySha256,
        ) ||
        !await _allMasksMatch(saved)) {
      return EvidenceSegmentationSnapshot(
        EvidenceSegmentationState.stale,
        analysis: saved,
        message: 'A saved mask artifact is missing or failed integrity.',
      );
    }
    return EvidenceSegmentationSnapshot(
      EvidenceSegmentationState.current,
      analysis: saved,
    );
  }

  @override
  Future<EvidenceSegmentationAnalysis> analyze(
    EvidenceImage evidence, {
    EvidenceSegmentationCancellation? cancellation,
    void Function()? onStarted,
  }) async {
    if (!executionEnabled) {
      throw const EvidenceSegmentationUnavailable(
        'Vehicle segmentation execution is not enabled in this build. '
        'MobileSAM redistribution approval is still required.',
      );
    }
    final token = cancellation ?? EvidenceSegmentationCancellation();
    return _queue.enqueue(() async {
      if (token.isCancelled) throw const EvidenceSegmentationCancelled();
      onStarted?.call();
      final detectionSnapshot = await detection.load(evidence);
      final detectionAnalysis = detectionSnapshot.analysis;
      if (detectionSnapshot.state != DetectionState.complete ||
          detectionAnalysis == null) {
        throw StateError('Current TASK007 detections are required.');
      }
      final metadata = detectionAnalysis.coordinateMetadata;
      if (metadata == null ||
          metadata.contractVersion != IrisImageCoordinateContract.version) {
        throw StateError('Current image-coordinate metadata is required.');
      }
      final prompts = <_Prompt>[];
      for (
        var index = 0;
        index < detectionAnalysis.detections.length;
        index++
      ) {
        final detected = detectionAnalysis.detections[index];
        if (EvidenceSegmentationModel.supportedClasses[detected.classId] !=
            detected.className) {
          continue;
        }
        final box = SegmentationPromptBox.fromDetection(
          detection: detected,
          metadata: metadata,
        );
        prompts.add(_Prompt(index, box));
      }
      if (prompts.isEmpty) {
        throw const EvidenceSegmentationUnsupported(
          'No current qualified car or motorcycle detection is available.',
        );
      }
      final actualSourceHash = await _sourceHash(evidence);
      if (actualSourceHash != evidence.sha256 ||
          actualSourceHash != detectionAnalysis.evidenceSha256) {
        throw StateError(
          'Evidence integrity or detection provenance is stale.',
        );
      }
      if (token.isCancelled) throw const EvidenceSegmentationCancelled();

      final analysisId =
          '${evidence.id}-${DateTime.now().microsecondsSinceEpoch}';
      final old = await repository.get(evidence.id);
      final relativeDirectory = storage.relativeDirectory(
        caseId: evidence.caseId,
        evidenceId: evidence.id,
        analysisId: analysisId,
      );
      final nativePaths = <String>{};
      try {
        final Map<String, Object?> result;
        try {
          result = await _runtime.run(
            absolutePath: await evidenceStorage.absolutePath(
              evidence.storedRelativePath,
            ),
            coordinateContractVersion: metadata.contractVersion,
            outputId: analysisId,
            boxes: prompts
                .map(
                  (prompt) => <String, Object>{
                    ...prompt.box.toChannelValue(),
                    'detectionIndex': prompt.detectionIndex,
                  },
                )
                .toList(growable: false),
          );
        } on PlatformException catch (error) {
          throw EvidenceSegmentationRuntimeFailure(
            error.code == 'insufficient_memory'
                ? 'The device could not provide enough memory for MobileSAM; no mask was saved.'
                : 'On-device segmentation failed (${error.code}); no mask was saved.',
          );
        }
        _captureNativePaths(result, nativePaths);
        if (token.isCancelled) throw const EvidenceSegmentationCancelled();
        _verifyRuntime(result, metadata, prompts.length);
        final overlayPath = result['overlayPath']! as String;
        final overlayHash = result['overlaySha256']! as String;
        nativePaths.add(overlayPath);
        final overlayRelative = path.join(relativeDirectory, 'overlay.png');
        await storage.copyAtomic(
          sourceAbsolutePath: overlayPath,
          destinationRelativePath: overlayRelative,
          expectedSha256: overlayHash,
        );

        final resultMasks = List<Object?>.from(
          result['promptMaskResults']! as List,
        );
        final masks = <EvidenceSegmentationMask>[];
        var decoderMs = 0.0;
        for (var i = 0; i < prompts.length; i++) {
          final raw = Map<String, Object?>.from(resultMasks[i]! as Map);
          final prompt = prompts[i];
          final maskPath = raw['maskPath']! as String;
          final maskHash = raw['maskFileSha256']! as String;
          nativePaths.add(maskPath);
          final relative = path.join(relativeDirectory, 'mask-$i.png');
          await storage.copyAtomic(
            sourceAbsolutePath: maskPath,
            destinationRelativePath: relative,
            expectedSha256: maskHash,
          );
          decoderMs += (raw['decoderMs'] as num?)?.toDouble() ?? 0;
          masks.add(
            EvidenceSegmentationMask(
              id: '$analysisId-$i',
              detectionIndex: prompt.detectionIndex,
              classId: prompt.box.classId,
              className: prompt.box.className,
              detectionScore: prompt.box.score,
              promptLeft: prompt.box.left,
              promptTop: prompt.box.top,
              promptRight: prompt.box.right,
              promptBottom: prompt.box.bottom,
              maskFileRelativePath: relative,
              maskSha256: maskHash,
              maskPixelCount: (raw['maskPixels']! as num).toInt(),
              predictedQuality: (raw['predictedQuality'] as num?)?.toDouble(),
            ),
          );
        }
        if (token.isCancelled) throw const EvidenceSegmentationCancelled();
        final analysis = EvidenceSegmentationAnalysis(
          id: analysisId,
          evidenceId: evidence.id,
          caseId: evidence.caseId,
          sourceEvidenceSha256: actualSourceHash,
          detectionAnalysisId: detectionAnalysis.id,
          detectorSha256: detectionAnalysis.detectorSha256,
          detectorContractVersion: detectionAnalysis.thresholdPolicyVersion,
          modelId: EvidenceSegmentationModel.id,
          modelSourceCommit: EvidenceSegmentationModel.sourceCommit,
          modelCheckpointSha256: EvidenceSegmentationModel.checkpointSha256,
          encoderSha256: EvidenceSegmentationModel.encoderSha256,
          decoderSha256: EvidenceSegmentationModel.decoderSha256,
          coordinateMetadata: metadata,
          analyzedAt: DateTime.now().toUtc(),
          overlayFileRelativePath: overlayRelative,
          overlaySha256: overlayHash,
          masks: List<EvidenceSegmentationMask>.unmodifiable(masks),
          encoderMs: (result['imageEncoderMs'] as num?)?.toDouble(),
          decoderMs: decoderMs,
          totalMs: (result['totalMs'] as num?)?.toDouble(),
          sampledPeakPssKb: (result['sampledPeakPssKb'] as num?)?.toInt(),
          baselinePssKb: (result['baselinePssKb'] as num?)?.toInt(),
        );
        await repository.save(analysis);
        if (old != null) {
          try {
            await storage.deleteDirectory(
              path.dirname(old.overlayFileRelativePath),
            );
          } on Object catch (error) {
            debugPrint(
              'IRIS could not remove superseded segmentation artifacts '
              '(${error.runtimeType}); the new verified analysis remains valid.',
            );
          }
        }
        return analysis;
      } on Object {
        await storage.deleteDirectory(relativeDirectory);
        rethrow;
      } finally {
        for (final nativePath in nativePaths) {
          try {
            final file = File(nativePath);
            if (await file.exists()) await file.delete();
          } on Object catch (error) {
            debugPrint(
              'IRIS could not remove a temporary segmentation artifact '
              '(${error.runtimeType}).',
            );
          }
        }
      }
    });
  }

  @override
  Future<String> overlayAbsolutePath(EvidenceSegmentationAnalysis analysis) =>
      storage.absolutePath(analysis.overlayFileRelativePath);

  void _verifyRuntime(
    Map<String, Object?> result,
    ImageCoordinateMetadata metadata,
    int expectedMasks,
  ) {
    final masks = result['promptMaskResults'];
    if (result['status'] != 'MASKS_GENERATED_ON_DEVICE' ||
        result['modelId'] != EvidenceSegmentationModel.id ||
        result['modelSourceCommit'] != EvidenceSegmentationModel.sourceCommit ||
        result['modelCheckpointSha256'] !=
            EvidenceSegmentationModel.checkpointSha256 ||
        result['encoderSha256'] != EvidenceSegmentationModel.encoderSha256 ||
        result['decoderSha256'] != EvidenceSegmentationModel.decoderSha256 ||
        result['modelLifecycle'] !=
            EvidenceSegmentationModel.runtimeLifecycle ||
        result['coordinateContractVersion'] != metadata.contractVersion ||
        masks is! List ||
        masks.length != expectedMasks) {
      throw StateError('Segmentation runtime provenance mismatch.');
    }
    for (final item in masks) {
      if (item is! Map) throw StateError('Malformed segmentation mask result.');
      final mask = Map<Object?, Object?>.from(item);
      if (mask['status'] != 'MASK_READY' ||
          (mask['maskPixels'] as num?)?.toInt() == null ||
          (mask['maskPixels'] as num).toInt() <= 0 ||
          mask['maskPath'] is! String ||
          mask['maskFileSha256'] is! String ||
          !_shaPattern.hasMatch(mask['maskFileSha256']! as String)) {
        throw StateError('No genuine segmentation mask was returned.');
      }
    }
    if (result['overlayPath'] is! String ||
        result['overlaySha256'] is! String ||
        !_shaPattern.hasMatch(result['overlaySha256']! as String)) {
      throw StateError('Segmentation overlay provenance is invalid.');
    }
  }

  void _captureNativePaths(Map<String, Object?> result, Set<String> paths) {
    final overlay = result['overlayPath'];
    if (overlay is String && overlay.isNotEmpty) paths.add(overlay);
    final masks = result['promptMaskResults'];
    if (masks is! List) return;
    for (final item in masks.whereType<Map>()) {
      final maskPath = item['maskPath'];
      if (maskPath is String && maskPath.isNotEmpty) paths.add(maskPath);
    }
  }

  Future<bool> _allMasksMatch(EvidenceSegmentationAnalysis analysis) async {
    for (final mask in analysis.masks) {
      if (EvidenceSegmentationModel.supportedClasses[mask.classId] !=
              mask.className ||
          !await storage.matches(mask.maskFileRelativePath, mask.maskSha256)) {
        return false;
      }
    }
    return analysis.masks.isNotEmpty;
  }

  Future<String> _sourceHash(EvidenceImage evidence) async {
    final file = File(
      await evidenceStorage.absolutePath(evidence.storedRelativePath),
    );
    if (!await file.exists()) throw StateError('Evidence file unavailable.');
    return (await sha256.bind(file.openRead()).first).toString();
  }

  bool _sameCoordinateMetadata(
    ImageCoordinateMetadata? left,
    ImageCoordinateMetadata right,
  ) => left != null && jsonEncode(left.toJson()) == jsonEncode(right.toJson());

  static final RegExp _shaPattern = RegExp(r'^[0-9a-f]{64}$');
}

class EvidenceSegmentationQueue {
  EvidenceSegmentationQueue();
  static final EvidenceSegmentationQueue shared = EvidenceSegmentationQueue();

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

class _Prompt {
  const _Prompt(this.detectionIndex, this.box);
  final int detectionIndex;
  final SegmentationPromptBox box;
}
