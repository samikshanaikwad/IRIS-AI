import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import '../../evidence/data/evidence_storage.dart';
import '../../evidence/domain/evidence_image.dart';
import '../../evidence_quality/application/evidence_quality_service.dart';
import '../../evidence_quality/domain/evidence_quality_assessment.dart';
import '../data/sqlite_evidence_depth_repository.dart';
import '../domain/evidence_depth.dart';

abstract interface class EvidenceDepthOperations {
  Future<EvidenceDepthSnapshot> load(EvidenceImage evidence);
  Future<EvidenceDepthAnalysis> analyze(EvidenceImage evidence);
}

class EvidenceDepthService implements EvidenceDepthOperations {
  EvidenceDepthService({required this.repository, required this.storage, required this.quality}) : _channel = const MethodChannel('com.iris.depth/v1');
  final SqliteEvidenceDepthRepository repository;
  final EvidenceStorage storage;
  final EvidenceQualityOperations quality;
  final MethodChannel _channel;
  static const artifactSha256 = 'f983ac210c302d37e0c07b075575426a4694a2b6eed6414fe66339bcb75a6830';
  @override
  Future<EvidenceDepthSnapshot> load(EvidenceImage evidence) async {
    final q = await quality.load(evidence);
    if (q.state != EvidenceQualitySnapshotState.current || q.assessment!.readiness == EvidenceReadiness.notUsable) return const EvidenceDepthSnapshot(DepthState.unavailable, message: 'A current usable quality assessment is required.');
    final a = await repository.get(evidence.id);
    if (a == null) return const EvidenceDepthSnapshot(DepthState.notAnalyzed);
    final current = await _hash(evidence);
    if (current != evidence.sha256 || current != a.evidenceSha256 || a.artifactSha256 != artifactSha256 || !await File(await storage.absolutePath(a.depthPath)).exists()) return const EvidenceDepthSnapshot(DepthState.stale, message: 'Saved relative depth is stale and requires reanalysis.');
    return EvidenceDepthSnapshot(DepthState.analyzed, analysis: a);
  }
  @override
  Future<EvidenceDepthAnalysis> analyze(EvidenceImage evidence) async {
    final q = await quality.load(evidence);
    if (q.state != EvidenceQualitySnapshotState.current || q.assessment!.readiness == EvidenceReadiness.notUsable) throw StateError('A current usable quality assessment is required.');
    final actual = await _hash(evidence);
    if (actual != evidence.sha256) throw StateError('Stored evidence integrity could not be verified.');
    final response = await _channel.invokeMapMethod<Object?, Object?>('run', {'absolutePath': await storage.absolutePath(evidence.storedRelativePath)}) ?? {};
    if (response['modelSha256'] != artifactSha256 || response['depth'] is! List) throw StateError('Depth runtime contract mismatch.');
    final values = (response['depth']! as List).map((v) => (v as num).toDouble()).toList();
    if (values.length != 518 * 518 || values.any((v) => !v.isFinite)) throw StateError('Depth output is invalid.');
    final relativePath = 'cases/${evidence.caseId}/derived/depth/${evidence.id}.f32';
    final absolute = await storage.absolutePath(relativePath);
    await File(absolute).parent.create(recursive: true);
    final temporary = File('$absolute.part');
    await temporary.writeAsBytes(Float32List.fromList(values).buffer.asUint8List(), flush: true);
    await temporary.rename(absolute);
    final a = EvidenceDepthAnalysis(evidenceId: evidence.id, evidenceSha256: actual, artifactSha256: artifactSha256, analyzedAt: DateTime.now().toUtc(), width: evidence.widthPx ?? 0, height: evidence.heightPx ?? 0, depthWidth: 518, depthHeight: 518, depthPath: relativePath, min: values.reduce((a, b) => a < b ? a : b), max: values.reduce((a, b) => a > b ? a : b), mean: values.reduce((a, b) => a + b) / values.length, inferenceMs: (response['inferenceMs'] as num?)?.toInt());
    await repository.save(a);
    return a;
  }
  Future<String> _hash(EvidenceImage e) async => (await sha256.bind(File(await storage.absolutePath(e.storedRelativePath)).openRead()).first).toString();
}
