import 'package:flutter/foundation.dart';

import '../domain/case_repository.dart';
import '../domain/incident_case.dart';

enum CaseCollectionState { loading, data, error }

class CaseController extends ChangeNotifier {
  CaseController(this._repository);

  final CaseRepository _repository;

  CaseCollectionState _state = CaseCollectionState.loading;
  List<IncidentCase> _cases = const <IncidentCase>[];
  bool _disposed = false;
  int _reloadGeneration = 0;

  CaseCollectionState get state => _state;
  List<IncidentCase> get cases => _cases;

  Future<void> loadCases() async {
    if (_disposed) {
      return;
    }
    _state = CaseCollectionState.loading;
    notifyListeners();
    await _reload();
  }

  Future<void> retry() => loadCases();

  Future<IncidentCase> createCase(String title) async {
    final IncidentCase incidentCase = await _repository.createCase(
      title: title,
    );
    await _reloadAfterMutation();
    return incidentCase;
  }

  Future<IncidentCase?> getCaseById(String id) {
    return _repository.getCaseById(id);
  }

  Future<IncidentCase> renameCase({
    required String id,
    required String title,
  }) async {
    final IncidentCase incidentCase = await _repository.renameCase(
      id: id,
      title: title,
    );
    await _reloadAfterMutation();
    return incidentCase;
  }

  Future<bool> deleteCase(String id) async {
    final bool deleted = await _repository.deleteCase(id);
    await _reloadAfterMutation();
    return deleted;
  }

  Future<void> _reloadAfterMutation() async {
    await _reload();
  }

  Future<void> _reload() async {
    final int generation = ++_reloadGeneration;
    try {
      final List<IncidentCase> cases = await _repository.getCases();
      if (_disposed || generation != _reloadGeneration) {
        return;
      }
      _cases = List<IncidentCase>.unmodifiable(cases);
      _state = CaseCollectionState.data;
      notifyListeners();
    } on Object {
      if (_disposed || generation != _reloadGeneration) {
        return;
      }
      _cases = const <IncidentCase>[];
      _state = CaseCollectionState.error;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _reloadGeneration++;
    super.dispose();
  }
}
