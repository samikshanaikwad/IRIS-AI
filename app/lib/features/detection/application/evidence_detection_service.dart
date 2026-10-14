import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import '../../evidence/data/evidence_storage.dart';
import '../../evidence/domain/evidence_image.dart';
import '../../evidence_quality/application/evidence_quality_service.dart';
import '../../evidence_quality/domain/evidence_quality_assessment.dart';
import '../data/sqlite_evidence_detection_repository.dart';
import '../domain/evidence_detection.dart';
import '../../evidence/domain/image_coordinate_contract.dart';

abstract interface class EvidenceDetectionOperations {
  Future<EvidenceDetectionSnapshot> load(EvidenceImage e);
  Future<EvidenceDetectionAnalysis> analyze(EvidenceImage e);
}

class EvidenceDetectionService implements EvidenceDetectionOperations {
  EvidenceDetectionService({
    required this.repository,
    required this.storage,
    required this.quality,
  }) : _channel = const MethodChannel('com.iris.detector/v1');
  final SqliteEvidenceDetectionRepository repository;
  final EvidenceStorage storage;
  final EvidenceQualityOperations quality;
  final MethodChannel _channel;
  static const detectorSha256 =
      '2e04c53bfeac0ac2a30c057c7e2a777594ce39baaac35a92f74fb1e8c4fc4e0b';
  static const detectorId = 'google-efficientdet-lite0-coco';
  static const contractVersion = 'v1-score-threshold-0.30';
  static const double scoreThreshold = 0.30;
  static const allowed = <int, String>{
    0: 'person',
    1: 'bicycle',
    2: 'car',
    3: 'motorcycle',
    5: 'bus',
    7: 'truck',
  };

  @override
  Future<EvidenceDetectionSnapshot> load(EvidenceImage e) async {
    final q = await quality.load(e);
    if (q.state != EvidenceQualitySnapshotState.current ||
        q.assessment!.readiness == EvidenceReadiness.notUsable) {
      return const EvidenceDetectionSnapshot(
        DetectionState.unavailable,
        message: 'A current usable quality assessment is required.',
      );
    }
    final a = await repository.get(e.id);
    if (a == null) {
      return const EvidenceDetectionSnapshot(DetectionState.notAnalyzed);
    }
    final actual = await _hash(e);
    return actual != e.sha256 ||
            a.evidenceSha256 != actual ||
            a.detectorSha256 != detectorSha256 ||
            a.thresholdPolicyVersion != contractVersion
        ? const EvidenceDetectionSnapshot(
            DetectionState.stale,
            message:
                'Stored detections no longer match the evidence or detector.',
          )
        : EvidenceDetectionSnapshot(DetectionState.complete, analysis: a);
  }

  @override
  Future<EvidenceDetectionAnalysis> analyze(EvidenceImage e) async {
    final q = await quality.load(e);
    if (q.state != EvidenceQualitySnapshotState.current ||
        q.assessment!.readiness == EvidenceReadiness.notUsable) {
      throw StateError('A current usable quality assessment is required.');
    }
    final actual = await _hash(e);
    if (actual != e.sha256) {
      throw StateError('Stored evidence integrity could not be verified.');
    }
    final response =
        await _channel.invokeMapMethod<Object?, Object?>('run', {
          'absolutePath': await storage.absolutePath(e.storedRelativePath),
        }) ??
        {};
    if (response['detectorSha256'] != detectorSha256 ||
        response['detections'] is! List ||
        response['thresholdPolicyVersion'] != contractVersion) {
      throw StateError('Detector runtime contract mismatch.');
    }
    final list = (response['detections']! as List)
        .map((raw) {
          final m = Map<Object?, Object?>.from(raw as Map);
          final id = (m['classId'] as num).toInt();
          final box = List<num>.from(m['box'] as List);
          final score = (m['score'] as num).toDouble();
          if (score < scoreThreshold) {
            return null;
          }
          if (!allowed.containsKey(id) ||
              !score.isFinite ||
              box.length != 4 ||
              box.any((v) => !v.isFinite || v < 0 || v > 1)) {
            throw StateError('Malformed detector output.');
          }
          return EvidenceDetection(
            classId: id,
            className: allowed[id]!,
            score: score,
            ymin: box[0].toDouble(),
            xmin: box[1].toDouble(),
            ymax: box[2].toDouble(),
            xmax: box[3].toDouble(),
          );
        })
        .whereType<EvidenceDetection>()
        .toList();
    final coordinateMetadata = _coordinateMetadata(response);
    final a = EvidenceDetectionAnalysis(
      id: '${e.id}-${DateTime.now().microsecondsSinceEpoch}',
      evidenceId: e.id,
      evidenceSha256: actual,
      detectorSha256: detectorSha256,
      thresholdPolicyVersion: contractVersion,
      analyzedAt: DateTime.now().toUtc(),
      inferenceMs: (response['inferenceMs'] as num?)?.toInt(),
      detections: list,
      coordinateMetadata: coordinateMetadata,
    );
    await repository.save(a);
    return a;
  }

  ImageCoordinateMetadata _coordinateMetadata(Map<Object?, Object?> response) {
    final raw = response['coordinateMetadata'];
    if (raw is! Map) {
      throw StateError('Detector coordinate metadata is unavailable.');
    }
    return ImageCoordinateMetadata.fromJson(Map<String, Object?>.from(raw));
  }

  Future<String> _hash(EvidenceImage e) async {
    final f = File(await storage.absolutePath(e.storedRelativePath));
    if (!await f.exists()) throw StateError('Evidence file unavailable.');
    return (await sha256.bind(f.openRead()).first).toString();
  }
}
