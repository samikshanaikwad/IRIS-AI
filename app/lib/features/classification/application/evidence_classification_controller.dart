import 'package:flutter/foundation.dart';

import '../../evidence/domain/evidence_image.dart';
import '../domain/evidence_classification.dart';
import 'evidence_classification_service.dart';

class EvidenceClassificationController extends ChangeNotifier {
  EvidenceClassificationController({
    required this.evidence,
    required EvidenceClassificationOperations operations,
  }) : _operations = operations;
  final EvidenceImage evidence;
  final EvidenceClassificationOperations _operations;
  EvidenceClassificationSnapshot _snapshot =
      const EvidenceClassificationSnapshot.notAnalyzed();
  bool _analyzing = false;
  String? _errorMessage;
  EvidenceClassificationSnapshot get snapshot => _snapshot;
  bool get analyzing => _analyzing;
  String? get errorMessage => _errorMessage;
  Future<void> load() async {
    try {
      _snapshot = await _operations.load(evidence);
      _errorMessage = null;
    } on Object {
      _snapshot = const EvidenceClassificationSnapshot.unavailable();
      _errorMessage = 'Classification status is unavailable.';
    }
    notifyListeners();
  }

  Future<bool> analyze() async {
    if (_analyzing) return false;
    _analyzing = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _operations.analyze(evidence);
      _snapshot = await _operations.load(evidence);
      return true;
    } on ClassificationUnavailableException catch (error) {
      _errorMessage = error.message;
    } on ClassificationIntegrityException {
      _errorMessage = 'Stored evidence integrity could not be verified.';
    } on Object {
      _errorMessage = 'Image classification could not be completed. Try again.';
    } finally {
      _analyzing = false;
      notifyListeners();
    }
    return false;
  }
}
