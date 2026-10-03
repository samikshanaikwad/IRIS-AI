import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../../depth/application/evidence_depth_service.dart';
import '../../depth/domain/evidence_depth.dart';
import '../../evidence/data/evidence_storage.dart';
import '../../evidence/domain/evidence_image.dart';
import '../data/sqlite_geometry_repository.dart';
import '../domain/relative_geometry.dart';

abstract interface class RelativeGeometryOperations {
  Future<GeometryRecord?> load(EvidenceImage evidence);
  Future<GeometryRecord> generate(EvidenceImage evidence);
  Future<RelativeGeometry> read(GeometryRecord record);
}

enum GeometryInspectionState { ready, missing, stale, invalid, unavailable }

class GeometryInspection {
  const GeometryInspection(this.state, {this.record, this.geometry});
  final GeometryInspectionState state;
  final GeometryRecord? record;
  final RelativeGeometry? geometry;
}

abstract interface class RelativeGeometryInspectionOperations {
  Future<GeometryInspection> inspect(EvidenceImage evidence);
}

class RelativeGeometryService
    implements
        RelativeGeometryOperations,
        RelativeGeometryInspectionOperations {
  RelativeGeometryService({
    required this.repository,
    required this.storage,
    required this.depth,
  });
  final SqliteGeometryRepository repository;
  final EvidenceStorage storage;
  final EvidenceDepthOperations depth;
  @override
  Future<GeometryInspection> inspect(EvidenceImage evidence) async {
    // Read-only diagnostic path; never generates geometry or changes its meaning.
    final record = await repository.get(evidence.id);
    if (record == null) {
      return const GeometryInspection(GeometryInspectionState.missing);
    }
    final snapshot = await depth.load(evidence);
    if (snapshot.state != DepthState.analyzed ||
        snapshot.analysis == null ||
        record.depthSha256 != evidence.sha256 ||
        record.depthSha256 != snapshot.analysis!.evidenceSha256 ||
        record.depthAnalyzedAt != snapshot.analysis!.analyzedAt) {
      return GeometryInspection(GeometryInspectionState.stale, record: record);
    }
    if (record.evidenceId != evidence.id ||
        record.algorithmVersion != 'relative-geometry-v1' ||
        record.coordinateVersion != 'iris-relative-camera-v1' ||
        record.pointCount <= 0 ||
        record.pointCount > 2048) {
      return GeometryInspection(
        GeometryInspectionState.invalid,
        record: record,
      );
    }
    if (!await File(await storage.absolutePath(record.path)).exists()) {
      return GeometryInspection(
        GeometryInspectionState.invalid,
        record: record,
      );
    }
    try {
      final points = await read(record);
      if (points.points.any(
        (p) => ![p.u, p.v].every((v) => v.isFinite && v >= 0 && v <= 1),
      )) {
        return GeometryInspection(
          GeometryInspectionState.invalid,
          record: record,
        );
      }
      return GeometryInspection(
        GeometryInspectionState.ready,
        record: record,
        geometry: points,
      );
    } on FormatException {
      return GeometryInspection(
        GeometryInspectionState.invalid,
        record: record,
      );
    } on FileSystemException {
      return GeometryInspection(
        GeometryInspectionState.unavailable,
        record: record,
      );
    }
  }

  @override
  Future<GeometryRecord?> load(EvidenceImage evidence) async {
    final record = await repository.get(evidence.id);
    if (record == null) return null;
    final d = await depth.load(evidence);
    if (d.state != DepthState.analyzed ||
        d.analysis == null ||
        record.depthSha256 != d.analysis!.evidenceSha256 ||
        record.depthAnalyzedAt != d.analysis!.analyzedAt ||
        !await File(await storage.absolutePath(record.path)).exists())
      return null;
    return record;
  }

  @override
  Future<GeometryRecord> generate(EvidenceImage evidence) async {
    final d = await depth.load(evidence);
    if (d.state != DepthState.analyzed || d.analysis == null)
      throw StateError('Analyze depth before generating geometry.');
    final viz = await depth.loadVisualization(d.analysis!);
    final geometry = buildRelativeGeometry(
      evidenceId: evidence.id,
      depthSha256: d.analysis!.evidenceSha256,
      depthAnalyzedAt: d.analysis!.analyzedAt,
      depth: viz.values,
      depthWidth: viz.width,
      depthHeight: viz.height,
      originalWidth: viz.originalWidth,
      originalHeight: viz.originalHeight,
    );
    final path =
        'cases/${evidence.caseId}/geometry/${evidence.id}/relative_points.f32';
    final absolute = await storage.absolutePath(path);
    await File(absolute).parent.create(recursive: true);
    final bytes = Float32List.fromList(
      geometry.points.expand((p) => <double>[p.x, p.y, p.z, p.u, p.v]).toList(),
    ).buffer.asUint8List();
    final temp = File('$absolute.part');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(absolute);
    final hash = sha256.convert(bytes).toString();
    final record = GeometryRecord(
      evidenceId: evidence.id,
      depthSha256: d.analysis!.evidenceSha256,
      depthAnalyzedAt: d.analysis!.analyzedAt,
      algorithmVersion: 'relative-geometry-v1',
      coordinateVersion: 'iris-relative-camera-v1',
      pointCount: geometry.points.length,
      path: path,
      sha256: hash,
      analyzedAt: DateTime.now().toUtc(),
    );
    await repository.save(record);
    return record;
  }

  @override
  Future<RelativeGeometry> read(GeometryRecord record) async {
    final bytes = await File(
      await storage.absolutePath(record.path),
    ).readAsBytes();
    if (bytes.length != record.pointCount * 5 * 4 ||
        sha256.convert(bytes).toString() != record.sha256)
      throw const FormatException('Geometry artifact is corrupt.');
    final values = Float32List.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.lengthInBytes ~/ 4,
    );
    final points = <RelativePoint>[];
    for (var i = 0; i < values.length; i += 5) {
      if (!values[i].isFinite ||
          !values[i + 1].isFinite ||
          !values[i + 2].isFinite)
        throw const FormatException('Geometry contains invalid values.');
      points.add(
        RelativePoint(
          x: values[i],
          y: values[i + 1],
          z: values[i + 2],
          u: values[i + 3],
          v: values[i + 4],
        ),
      );
    }
    return RelativeGeometry(
      points: points,
      evidenceId: record.evidenceId,
      depthSha256: record.depthSha256,
      depthAnalyzedAt: record.depthAnalyzedAt,
      width: 1,
      height: 1,
    );
  }
}
