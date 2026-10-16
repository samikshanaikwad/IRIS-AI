import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import '../../evidence/data/evidence_storage.dart';

class EvidenceSegmentationStorage {
  EvidenceSegmentationStorage(this._storage);

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
      'segmentation',
      evidenceId,
      analysisId,
    );
  }

  Future<void> copyAtomic({
    required String sourceAbsolutePath,
    required String destinationRelativePath,
    required String expectedSha256,
  }) async {
    final source = File(sourceAbsolutePath);
    if (!await source.exists()) {
      throw const FileSystemException('Segmentation artifact is unavailable.');
    }
    final actual = await _hash(source);
    if (actual != expectedSha256) {
      throw StateError('Segmentation artifact integrity mismatch.');
    }
    final destination = File(
      await _storage.absolutePath(destinationRelativePath),
    );
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.part');
    if (await temporary.exists()) await temporary.delete();
    try {
      await source.openRead().pipe(temporary.openWrite());
      if (await _hash(temporary) != expectedSha256) {
        throw StateError('Copied segmentation artifact failed integrity.');
      }
      if (await destination.exists()) await destination.delete();
      await temporary.rename(destination.path);
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
    final absolute = await _storage.absolutePath(relativeDirectory);
    final directory = Directory(absolute);
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<String> absolutePath(String relativePath) =>
      _storage.absolutePath(relativePath);

  Future<String> _hash(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  void _identifier(String value, String name) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(value)) {
      throw ArgumentError.value(value, name, 'Unsafe identifier.');
    }
  }
}
