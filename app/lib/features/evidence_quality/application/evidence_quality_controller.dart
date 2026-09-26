import 'package:flutter/foundation.dart';

import '../../evidence/domain/evidence_image.dart';
import '../domain/evidence_quality_assessment.dart';
import 'evidence_quality_service.dart';

class EvidenceQualityController extends ChangeNotifier {
  EvidenceQualityController({
    required this.evidence,
    required EvidenceQualityOperations operations,
  }) : _operations = operations;

  final EvidenceImage evidence;
  final EvidenceQualityOperations _operations;

  EvidenceQualitySnapshot _snapshot =
      const EvidenceQualitySnapshot.notAssessed();
  bool _loading = true;
  bool _assessing = false;
  bool _disposed = false;
  String? _errorMessage;

  EvidenceQualitySnapshot get snapshot => _snapshot;
  bool get loading => _loading;
  bool get assessing => _assessing;
  String? get errorMessage => _errorMessage;

  Future<void> load() async {
    if (_disposed) {
      return;
    }
    _loading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _snapshot = await _operations.load(evidence);
    } on Object {
      _snapshot = const EvidenceQualitySnapshot.unavailable();
      _errorMessage =
          'The saved quality assessment could not be read from local storage.';
    } finally {
      if (!_disposed) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> assess() async {
    if (_disposed || _assessing) {
      return false;
    }
    _assessing = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final EvidenceQualityAssessment assessment = await _operations.assess(
        evidence,
      );
      _snapshot = EvidenceQualitySnapshot.current(assessment);
      return true;
    } on EvidenceQualityPersistenceException {
      _errorMessage =
          'Quality checks completed, but the assessment could not be saved.';
      return false;
    } on Object {
      _errorMessage = 'Evidence quality assessment could not be completed.';
      return false;
    } finally {
      if (!_disposed) {
        _assessing = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
