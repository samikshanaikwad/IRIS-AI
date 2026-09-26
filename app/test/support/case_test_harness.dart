import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:iris/app/iris_application_services.dart';
import 'package:iris/core/database/iris_database.dart';
import 'package:iris/features/cases/data/sqlite_case_repository.dart';

class CaseTestHarness {
  CaseTestHarness._({
    required this.directory,
    required this.database,
    required this.repository,
    required this.services,
  });

  final Directory directory;
  final IrisDatabase database;
  final SqliteCaseRepository repository;
  final IrisApplicationServices services;

  static Future<CaseTestHarness> create() async {
    sqfliteFfiInit();
    final Directory directory = await Directory.systemTemp.createTemp(
      'iris_case_test_',
    );
    final IrisDatabase database = IrisDatabase(
      factory: databaseFactoryFfi,
      databasePath: path.join(directory.path, 'test_iris.db'),
    );
    await database.open();
    final SqliteCaseRepository repository = SqliteCaseRepository(database);
    return CaseTestHarness._(
      directory: directory,
      database: database,
      repository: repository,
      services: IrisApplicationServices(
        caseRepository: repository,
        close: database.close,
      ),
    );
  }

  Future<void> dispose() async {
    await services.close();
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  }
}
