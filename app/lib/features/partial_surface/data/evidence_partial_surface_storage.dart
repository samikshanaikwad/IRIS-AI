import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import '../../evidence/data/evidence_storage.dart';
import '../domain/evidence_partial_surface.dart';

/// Durable storage for derived visible-surface artifacts.  This never writes
/// to the immutable original evidence file or to segmentation/depth artifacts.
class EvidencePartialSurfaceStorage {
  EvidencePartialSurfaceStorage(this._storage);

  static const int _magic = 0x49505331; // IPS1
  static const int _version = 1;
  final EvidenceStorage _storage;

  String relativeDirectory({
    required String caseId,
    required String evidenceId,
    required String analysisId,
  }) {
    _identifier(caseId, 'caseId');
    _identifier(evidenceId, 'evidenceId');
    _identifier(analysisId, 'analysisId');
    return path.join(
      'cases',
      caseId,
      'derived',
      'partial_surfaces',
      evidenceId,
      analysisId,
    );
  }

  Future<String> absolutePath(String relativePath) =>
      _storage.absolutePath(relativePath);

  Future<void> copyAtomic({
    required String sourceAbsolutePath,
    required String destinationRelativePath,
    required String expectedSha256,
  }) async {
    final source = File(sourceAbsolutePath);
    if (!await source.exists()) {
      throw const FileSystemException(
        'Partial surface artifact is unavailable.',
      );
    }
    if (await _hash(source) != expectedSha256) {
      throw StateError('Partial surface artifact integrity mismatch.');
    }
    final target = File(await _storage.absolutePath(destinationRelativePath));
    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.part');
    if (await temporary.exists()) await temporary.delete();
    try {
      await source.openRead().pipe(temporary.openWrite());
      if (await _hash(temporary) != expectedSha256) {
        throw StateError('Copied partial surface artifact failed integrity.');
      }
      if (await target.exists()) await target.delete();
      await temporary.rename(target.path);
    } on Object {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  Future<bool> matches(String relativePath, String expectedSha256) async {
    final file = File(await _storage.absolutePath(relativePath));
    return await file.exists() && await _hash(file) == expectedSha256;
  }

  Future<void> deleteDirectory(String relativeDirectory) async {
    final directory = Directory(await _storage.absolutePath(relativeDirectory));
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<EvidencePartialSurfaceMesh> read(
    EvidencePartialSurfacePart part,
  ) async {
    final file = File(await _storage.absolutePath(part.meshFileRelativePath));
    if (!await file.exists() || await _hash(file) != part.meshSha256) {
      throw const FormatException('Partial surface artifact is unavailable.');
    }
    final bytes = await file.readAsBytes();
    const headerBytes = 16, vertexBytes = 32, triangleBytes = 12;
    if (bytes.length < headerBytes) {
      throw const FormatException('Partial surface artifact is truncated.');
    }
    final data = ByteData.sublistView(bytes);
    final magic = data.getUint32(0, Endian.little);
    final version = data.getUint32(4, Endian.little);
    final verticesCount = data.getUint32(8, Endian.little);
    final trianglesCount = data.getUint32(12, Endian.little);
    if (magic != _magic ||
        version != _version ||
        verticesCount != part.vertexCount ||
        trianglesCount != part.triangleCount ||
        verticesCount > EvidencePartialSurfaceProcessing.maxVerticesPerPart ||
        trianglesCount > EvidencePartialSurfaceProcessing.maxTrianglesPerPart ||
        bytes.length !=
            headerBytes +
                verticesCount * vertexBytes +
                trianglesCount * triangleBytes) {
      throw const FormatException(
        'Partial surface artifact contract is invalid.',
      );
    }
    var offset = headerBytes;
    final vertices = <PartialSurfaceVertex>[];
    for (var i = 0; i < verticesCount; i++) {
      final x = data.getFloat32(offset, Endian.little);
      final y = data.getFloat32(offset + 4, Endian.little);
      final z = data.getFloat32(offset + 8, Endian.little);
      final u = data.getFloat32(offset + 12, Endian.little);
      final v = data.getFloat32(offset + 16, Endian.little);
      final argb = data.getUint32(offset + 20, Endian.little);
      if (![x, y, z, u, v].every((value) => value.isFinite) ||
          u < 0 ||
          u > 1 ||
          v < 0 ||
          v > 1) {
        throw const FormatException('Partial surface vertex is invalid.');
      }
      vertices.add(
        PartialSurfaceVertex(x: x, y: y, z: z, u: u, v: v, argb: argb),
      );
      offset += vertexBytes;
    }
    final triangles = <PartialSurfaceTriangle>[];
    for (var i = 0; i < trianglesCount; i++) {
      final a = data.getUint32(offset, Endian.little);
      final b = data.getUint32(offset + 4, Endian.little);
      final c = data.getUint32(offset + 8, Endian.little);
      if (a >= verticesCount ||
          b >= verticesCount ||
          c >= verticesCount ||
          a == b ||
          b == c ||
          a == c) {
        throw const FormatException('Partial surface triangle is invalid.');
      }
      triangles.add(PartialSurfaceTriangle(a, b, c));
      offset += triangleBytes;
    }
    return EvidencePartialSurfaceMesh(
      part: part,
      vertices: List<PartialSurfaceVertex>.unmodifiable(vertices),
      triangles: List<PartialSurfaceTriangle>.unmodifiable(triangles),
    );
  }

  Future<String> hashRelativePath(String relativePath) async =>
      _hash(File(await _storage.absolutePath(relativePath)));

  Future<String> _hash(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  void _identifier(String value, String name) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(value)) {
      throw ArgumentError.value(value, name, 'Unsafe identifier.');
    }
  }
}
