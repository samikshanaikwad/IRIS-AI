import '../domain/case_location.dart';
import '../domain/environment_context.dart';

abstract interface class EnvironmentProvider {
  String get name;
  Future<EnvironmentSourceSnapshot> fetch(CaseLocation location);
}
