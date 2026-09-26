import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

typedef EvidenceRootProvider = Future<Directory> Function();

class EvidenceStorage {
  EvidenceStorage({EvidenceRootProvider? rootProvider})
    : _rootProvider = rootProvider ?? _defaultRoot;

  final EvidenceRootProvider _rootProvider;

  static Future<Directory> _defaultRoot() async {
    final Directory support = await getApplicationSupportDirectory();
    return Directory(path.join(support.path, 'iris'));
  }

  Future<String> absolutePath(String relativePath) async {
    final List<String> parts = path.split(relativePath);
    if (path.isAbsolute(relativePath) ||
        parts.any((String part) => part == '..')) {
      throw ArgumentError.value(relativePath, 'relativePath', 'Unsafe path.');
    }
    final Directory root = await _rootProvider();
    return path.join(root.path, relativePath);
  }

  String relativeEvidencePath({
    required String caseId,
    required String evidenceId,
    required String sourcePath,
  }) {
    _validateIdentifier(caseId, 'caseId');
    _validateIdentifier(evidenceId, 'evidenceId');
    final String extension = _safeExtension(sourcePath);
    return path.join('cases', caseId, 'evidence', '$evidenceId$extension');
  }

  Future<File> copyOriginal({
    required String sourcePath,
    required String relativePath,
  }) async {
    final File source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Selected evidence file is unavailable.');
    }
    final String destinationPath = await absolutePath(relativePath);
    final File destination = File(destinationPath);
    await destination.parent.create(recursive: true);
    final File temporary = File('$destinationPath.part');
    if (await temporary.exists()) {
      await temporary.delete();
    }
    try {
      await source.openRead().pipe(temporary.openWrite());
      return await temporary.rename(destinationPath);
    } on Object {
      if (await temporary.exists()) {
        await temporary.delete();
      }
      rethrow;
    }
  }

  Future<void> deleteRelative(String relativePath) async {
    final File file = File(await absolutePath(relativePath));
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<StagedDeletion> stageRelative(String relativePath) async {
    final File original = File(await absolutePath(relativePath));
    if (!await original.exists()) {
      return const StagedDeletion.absent();
    }
    final File staged = File('${original.path}.pending-delete');
    if (await staged.exists()) {
      await staged.delete();
    }
    await original.rename(staged.path);
    return StagedDeletion(originalPath: original.path, stagedPath: staged.path);
  }

  Future<StagedDeletion> stageCaseDirectory(String caseId) async {
    _validateIdentifier(caseId, 'caseId');
    final Directory root = await _rootProvider();
    final Directory original = Directory(path.join(root.path, 'cases', caseId));
    if (!await original.exists()) {
      return const StagedDeletion.absent();
    }
    final Directory staged = Directory('${original.path}.pending-delete');
    if (await staged.exists()) {
      await staged.delete(recursive: true);
    }
    await original.rename(staged.path);
    return StagedDeletion(originalPath: original.path, stagedPath: staged.path);
  }

  Future<void> deleteCaseDirectory(String caseId) async {
    _validateIdentifier(caseId, 'caseId');
    final Directory root = await _rootProvider();
    final Directory directory = Directory(
      path.join(root.path, 'cases', caseId),
    );
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  void _validateIdentifier(String value, String name) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(value)) {
      throw ArgumentError.value(value, name, 'Unsafe identifier.');
    }
  }

  String _safeExtension(String sourcePath) {
    final String value = path.extension(sourcePath).toLowerCase();
    const Set<String> allowed = <String>{
      '.jpg',
      '.jpeg',
      '.png',
      '.webp',
      '.heic',
      '.heif',
      '.gif',
      '.bmp',
    };
    return allowed.contains(value) ? value : '.bin';
  }
}

class StagedDeletion {
  const StagedDeletion({required this.originalPath, required this.stagedPath})
    : exists = true;

  const StagedDeletion.absent()
    : originalPath = null,
      stagedPath = null,
      exists = false;

  final String? originalPath;
  final String? stagedPath;
  final bool exists;

  Future<void> restore() async {
    if (!exists) {
      return;
    }
    final FileSystemEntityType type = await FileSystemEntity.type(stagedPath!);
    if (type == FileSystemEntityType.directory) {
      await Directory(stagedPath!).rename(originalPath!);
    } else if (type == FileSystemEntityType.file) {
      await File(stagedPath!).rename(originalPath!);
    }
  }

  Future<void> finalize() async {
    if (!exists) {
      return;
    }
    final FileSystemEntityType type = await FileSystemEntity.type(stagedPath!);
    if (type == FileSystemEntityType.directory) {
      await Directory(stagedPath!).delete(recursive: true);
    } else if (type == FileSystemEntityType.file) {
      await File(stagedPath!).delete();
    }
  }
}
