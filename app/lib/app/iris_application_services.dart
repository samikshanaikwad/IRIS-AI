import '../core/database/iris_database.dart';
import '../features/cases/data/sqlite_case_repository.dart';
import '../features/cases/domain/case_repository.dart';

class IrisApplicationServices {
  IrisApplicationServices({
    required this.caseRepository,
    Future<void> Function()? close,
  }) : _close = close;

  factory IrisApplicationServices.production() {
    final IrisDatabase database = IrisDatabase();
    return IrisApplicationServices.fromDatabase(database);
  }

  factory IrisApplicationServices.fromDatabase(IrisDatabase database) {
    return IrisApplicationServices(
      caseRepository: SqliteCaseRepository(database),
      close: database.close,
    );
  }

  final CaseRepository caseRepository;
  final Future<void> Function()? _close;

  Future<void> close() async {
    await _close?.call();
  }
}
