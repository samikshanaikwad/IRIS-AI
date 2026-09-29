import 'package:flutter/services.dart';
import '../../evidence/data/evidence_storage.dart';
import '../../evidence/domain/evidence_image.dart';
import '../data/sqlite_case_location_repository.dart';
import '../domain/case_location.dart';

class CaseLocationService {
  CaseLocationService({required this.repository, required this.storage}) : _channel = const MethodChannel('com.iris.location/v1');
  final SqliteCaseLocationRepository repository;
  final EvidenceStorage storage;
  final MethodChannel _channel;
  Future<CaseLocation?> current(String caseId) async {
    final raw = Map<String, dynamic>.from(await _channel.invokeMethod<Map<Object?, Object?>>('currentLocation') ?? {});
    if (raw['status'] != 'AVAILABLE') return null;
    return _candidate(caseId, (raw['latitude'] as num).toDouble(), (raw['longitude'] as num).toDouble(), CaseLocationSource.deviceCurrentLocation);
  }
  Future<CaseLocation?> evidenceGps(String caseId, EvidenceImage evidence) async {
    final raw = Map<String, dynamic>.from(await _channel.invokeMethod<Map<Object?, Object?>>('readGps', {'path': await storage.absolutePath(evidence.storedRelativePath)}) ?? {});
    if (raw['status'] != 'AVAILABLE') return null;
    return _candidate(caseId, (raw['latitude'] as num).toDouble(), (raw['longitude'] as num).toDouble(), CaseLocationSource.evidenceExif, sourceEvidenceId: evidence.id);
  }
  Future<void> confirm(CaseLocation value) => repository.save(value);
  CaseLocation _candidate(String caseId, double latitude, double longitude, CaseLocationSource source, {String? sourceEvidenceId}) => CaseLocation(caseId: caseId, latitude: latitude, longitude: longitude, source: source, sourceEvidenceId: sourceEvidenceId, updatedAt: DateTime.now());
}
