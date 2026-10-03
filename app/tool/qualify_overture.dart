// Development-only live control; has no database or app persistence access.
import 'dart:convert';
import 'dart:io';
import 'package:iris/features/location/data/overture_environment_provider.dart';
import 'package:iris/features/location/domain/case_location.dart';

Future<void> main() async {
  final result = await OvertureEnvironmentProvider().fetch(
    CaseLocation(
      caseId: 'development-control-only',
      latitude: 51.0538,
      longitude: 3.7250,
      source: CaseLocationSource.mapSelection,
      updatedAt: DateTime.now(),
    ),
  );
  stdout.writeln(
    jsonEncode({
      'provider': result.provider,
      'release': result.release,
      'state': result.state.storageValue,
      'buildings': result.features.map((f) => f.sourceId).toSet().length,
      'fragments': result.features.length,
      'withSourceHeight': result.features
          .where((f) => f.sourceHeight != null)
          .map((f) => f.sourceId)
          .toSet()
          .length,
      'detail': result.detail,
      'attributeKeys': result.features.isEmpty
          ? []
          : result.features.first.tags.keys.toList(),
    }),
  );
  if (!result.state.isSuccess || result.features.isEmpty) {
    throw StateError('Live control did not qualify');
  }
}
