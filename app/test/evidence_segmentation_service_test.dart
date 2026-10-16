import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/detection/application/evidence_detection_service.dart';
import 'package:iris/features/detection/domain/evidence_detection.dart';
import 'package:iris/features/evidence/data/evidence_storage.dart';
import 'package:iris/features/evidence/domain/evidence_image.dart';
import 'package:iris/features/evidence/domain/image_coordinate_contract.dart';
import 'package:iris/features/segmentation/application/evidence_segmentation_service.dart';
import 'package:iris/features/segmentation/data/evidence_segmentation_storage.dart';
import 'package:iris/features/segmentation/domain/evidence_segmentation.dart';
import 'package:iris/features/segmentation/domain/evidence_segmentation_repository.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory directory;
  late EvidenceStorage evidenceStorage;
  late EvidenceImage evidence;
  late _MemoryRepository repository;
  late _DetectionOperations detection;
  late _Runtime runtime;

  final metadata = ImageCoordinateMetadata.create(
    raw: const ImageExtent(1600, 900),
    orientation: IrisExifOrientation.normal,
    canvas: const ImageExtent(320, 320),
    mode: RasterResizeMode.containLetterbox,
    rounding: RasterRounding.floor,
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('iris_segment_');
    evidenceStorage = EvidenceStorage(rootProvider: () async => directory);
    const bytes = <int>[1, 2, 3, 4];
    final relative = path.join('cases', 'case', 'evidence', 'evidence.jpg');
    final source = File(await evidenceStorage.absolutePath(relative));
    await source.parent.create(recursive: true);
    await source.writeAsBytes(bytes, flush: true);
    evidence = EvidenceImage(
      id: 'evidence',
      caseId: 'case',
      storedRelativePath: relative,
      source: EvidenceSource.gallery,
      importedAt: DateTime.utc(2026),
      fileSizeBytes: bytes.length,
      sha256: sha256.convert(bytes).toString(),
    );
    repository = _MemoryRepository();
    detection = _DetectionOperations(_analysis(evidence, metadata));
    runtime = _Runtime(directory);
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  EvidenceSegmentationService service({bool enabled = true}) =>
      EvidenceSegmentationService(
        repository: repository,
        storage: EvidenceSegmentationStorage(evidenceStorage),
        evidenceStorage: evidenceStorage,
        detection: detection,
        runtime: runtime,
        executionEnabled: enabled,
        queue: EvidenceSegmentationQueue(),
      );

  test('persists real runtime mask provenance and reloads it', () async {
    final operations = service();
    final result = await operations.analyze(evidence);

    expect(result.masks, hasLength(1));
    expect(result.masks.single.className, 'motorcycle');
    expect(result.sourceEvidenceSha256, evidence.sha256);
    expect(result.detectionAnalysisId, 'detection');
    expect(
      result.modelCheckpointSha256,
      EvidenceSegmentationModel.checkpointSha256,
    );
    expect(runtime.calls, 1);
    expect(
      (await operations.load(evidence)).state,
      EvidenceSegmentationState.current,
    );
    expect(
      File(await operations.overlayAbsolutePath(result)).existsSync(),
      isTrue,
    );
  });

  test('unsupported TASK007 class never invokes MobileSAM', () async {
    detection.analysis = _analysis(
      evidence,
      metadata,
      detection: const EvidenceDetection(
        classId: 5,
        className: 'bus',
        score: 0.9,
        ymin: 0.3,
        xmin: 0.3,
        ymax: 0.7,
        xmax: 0.7,
      ),
    );

    await expectLater(
      service().analyze(evidence),
      throwsA(isA<EvidenceSegmentationUnsupported>()),
    );
    expect(runtime.calls, 0);
    expect(repository.value, isNull);
  });

  test(
    'detector failure never invokes MobileSAM or creates a record',
    () async {
      detection.snapshotState = DetectionState.error;
      await expectLater(service().analyze(evidence), throwsStateError);
      expect(runtime.calls, 0);
      expect(repository.value, isNull);
    },
  );

  test(
    'artifact hash failure leaves no valid record or derived directory',
    () async {
      runtime.returnWrongHash = true;
      await expectLater(service().analyze(evidence), throwsStateError);
      expect(repository.value, isNull);
      final derived = Directory(
        path.join(directory.path, 'cases', 'case', 'derived', 'segmentation'),
      );
      expect(
        await derived.exists()
            ? await derived.list(recursive: true).toList()
            : <FileSystemEntity>[],
        isEmpty,
      );
    },
  );

  test('source change marks a persisted mask stale', () async {
    final operations = service();
    await operations.analyze(evidence);
    final source = File(
      await evidenceStorage.absolutePath(evidence.storedRelativePath),
    );
    await source.writeAsBytes(<int>[9, 9, 9], flush: true);

    final snapshot = await operations.load(evidence);
    expect(snapshot.state, EvidenceSegmentationState.stale);
  });

  test('changed TASK007 analysis makes persisted masks stale', () async {
    final operations = service();
    await operations.analyze(evidence);
    detection.analysis = EvidenceDetectionAnalysis(
      id: 'replacement-detection',
      evidenceId: detection.analysis.evidenceId,
      evidenceSha256: detection.analysis.evidenceSha256,
      detectorSha256: detection.analysis.detectorSha256,
      thresholdPolicyVersion: detection.analysis.thresholdPolicyVersion,
      analyzedAt: detection.analysis.analyzedAt,
      inferenceMs: detection.analysis.inferenceMs,
      detections: detection.analysis.detections,
      coordinateMetadata: detection.analysis.coordinateMetadata,
    );

    expect(
      (await operations.load(evidence)).state,
      EvidenceSegmentationState.stale,
    );
  });

  test('cancelled queued work never invokes the runtime or persists', () async {
    final cancellation = EvidenceSegmentationCancellation()..cancel();
    await expectLater(
      service().analyze(evidence, cancellation: cancellation),
      throwsA(isA<EvidenceSegmentationCancelled>()),
    );
    expect(runtime.calls, 0);
    expect(repository.value, isNull);
  });

  test('debug execution gate fails closed before model invocation', () async {
    await expectLater(
      service(enabled: false).analyze(evidence),
      throwsA(isA<EvidenceSegmentationUnavailable>()),
    );
    expect(runtime.calls, 0);
  });

  test('queue serializes concurrent model runs', () async {
    final queue = EvidenceSegmentationQueue();
    var concurrent = 0;
    var maximum = 0;
    Future<int> work(int value) => queue.enqueue(() async {
      concurrent++;
      if (concurrent > maximum) maximum = concurrent;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      concurrent--;
      return value;
    });

    expect(await Future.wait(<Future<int>>[work(1), work(2)]), <int>[1, 2]);
    expect(maximum, 1);
  });
}

EvidenceDetectionAnalysis _analysis(
  EvidenceImage evidence,
  ImageCoordinateMetadata metadata, {
  EvidenceDetection detection = const EvidenceDetection(
    classId: 3,
    className: 'motorcycle',
    score: 0.92,
    ymin: 0.3,
    xmin: 0.2,
    ymax: 0.7,
    xmax: 0.8,
  ),
}) => EvidenceDetectionAnalysis(
  id: 'detection',
  evidenceId: evidence.id,
  evidenceSha256: evidence.sha256,
  detectorSha256: EvidenceDetectionService.detectorSha256,
  thresholdPolicyVersion: EvidenceDetectionService.contractVersion,
  analyzedAt: DateTime.utc(2026),
  inferenceMs: 12,
  detections: <EvidenceDetection>[detection],
  coordinateMetadata: metadata,
);

class _MemoryRepository implements EvidenceSegmentationRepository {
  EvidenceSegmentationAnalysis? value;
  @override
  Future<EvidenceSegmentationAnalysis?> get(String evidenceId) async => value;
  @override
  Future<void> save(EvidenceSegmentationAnalysis analysis) async {
    value = analysis;
  }
}

class _DetectionOperations implements EvidenceDetectionOperations {
  _DetectionOperations(this.analysis);
  EvidenceDetectionAnalysis analysis;
  DetectionState snapshotState = DetectionState.complete;
  @override
  Future<EvidenceDetectionAnalysis> analyze(EvidenceImage e) async => analysis;
  @override
  Future<EvidenceDetectionSnapshot> load(EvidenceImage e) async =>
      EvidenceDetectionSnapshot(
        snapshotState,
        analysis: snapshotState == DetectionState.complete ? analysis : null,
      );
}

class _Runtime implements EvidenceSegmentationRuntime {
  _Runtime(this.directory);
  final Directory directory;
  int calls = 0;
  bool returnWrongHash = false;

  @override
  Future<Map<String, Object?>> run({
    required String absolutePath,
    required String coordinateContractVersion,
    required String outputId,
    required List<Map<String, Object>> boxes,
  }) async {
    calls++;
    final mask = File(path.join(directory.path, '$outputId-mask.png'));
    final overlay = File(path.join(directory.path, '$outputId-overlay.png'));
    await mask.writeAsBytes(<int>[1, 3, 3, 7], flush: true);
    await overlay.writeAsBytes(<int>[2, 4, 6, 8], flush: true);
    final maskHash = sha256.convert(await mask.readAsBytes()).toString();
    final overlayHash = sha256.convert(await overlay.readAsBytes()).toString();
    return <String, Object?>{
      'status': 'MASKS_GENERATED_ON_DEVICE',
      'modelId': EvidenceSegmentationModel.id,
      'modelSourceCommit': EvidenceSegmentationModel.sourceCommit,
      'modelCheckpointSha256': EvidenceSegmentationModel.checkpointSha256,
      'encoderSha256': EvidenceSegmentationModel.encoderSha256,
      'decoderSha256': EvidenceSegmentationModel.decoderSha256,
      'modelLifecycle': EvidenceSegmentationModel.runtimeLifecycle,
      'coordinateContractVersion': coordinateContractVersion,
      'imageEncoderMs': 2000.0,
      'totalMs': 2500.0,
      'sampledPeakPssKb': 900000,
      'baselinePssKb': 200000,
      'overlayPath': overlay.path,
      'overlaySha256': returnWrongHash ? '0' * 64 : overlayHash,
      'promptMaskResults': boxes
          .map(
            (_) => <String, Object?>{
              'status': 'MASK_READY',
              'decoderMs': 200.0,
              'maskPixels': 100,
              'predictedQuality': 0.9,
              'maskPath': mask.path,
              'maskFileSha256': maskHash,
            },
          )
          .toList(),
    };
  }
}
