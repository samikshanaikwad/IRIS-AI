import 'package:flutter/foundation.dart';

import '../data/evidence_storage.dart';
import '../domain/evidence_image.dart';
import '../domain/evidence_repository.dart';
import 'evidence_acquisition_service.dart';

class EvidenceController extends ChangeNotifier {
  EvidenceController({
    required this.caseId,
    required EvidenceRepository repository,
    required EvidenceStorage storage,
    required EvidenceAcquisitionService acquisition,
  }) : _repository = repository,
       _storage = storage,
       _acquisition = acquisition;

  final String caseId;
  final EvidenceRepository _repository;
  final EvidenceStorage _storage;
  final EvidenceAcquisitionService _acquisition;

  List<EvidenceImage> _items = const <EvidenceImage>[];
  bool _loading = true;
  bool _failed = false;
  bool _disposed = false;

  List<EvidenceImage> get items => _items;
  bool get loading => _loading;
  bool get failed => _failed;

  Future<void> load() async {
    if (_disposed) {
      return;
    }
    _loading = true;
    _failed = false;
    notifyListeners();
    try {
      _items = List<EvidenceImage>.unmodifiable(
        await _repository.getForCase(caseId),
      );
    } on Object {
      _failed = true;
    } finally {
      if (!_disposed) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<EvidenceImportSummary> importAll(
    List<EvidenceImportCandidate> candidates,
  ) async {
    final EvidenceImportSummary summary = await _acquisition.importAll(
      caseId: caseId,
      candidates: candidates,
    );
    await load();
    return summary;
  }

  Future<bool> delete(EvidenceImage evidence) async {
    final StagedDeletion staged = await _storage.stageRelative(
      evidence.storedRelativePath,
    );
    try {
      final bool deleted = await _repository.delete(evidence.id);
      if (!deleted) {
        await staged.restore();
        return false;
      }
      await staged.finalize();
      await load();
      return true;
    } on Object {
      await staged.restore();
      rethrow;
    }
  }

  Future<String> absolutePath(EvidenceImage evidence) {
    return _storage.absolutePath(evidence.storedRelativePath);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
