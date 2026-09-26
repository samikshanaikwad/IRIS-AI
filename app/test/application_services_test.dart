import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:iris/app/iris_application_services.dart';
import 'package:iris/core/database/iris_database.dart';
import 'package:iris/features/cases/domain/incident_case.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'application services retain the supplied database until close',
    () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'iris_services_test_',
      );
      final String databasePath = path.join(directory.path, 'services.db');
      final IrisDatabase database = IrisDatabase(
        factory: databaseFactoryFfi,
        databasePath: databasePath,
      );
      final IrisApplicationServices services =
          IrisApplicationServices.fromDatabase(database);
      addTearDown(() async {
        await services.close();
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      });

      expect(database.isOpen, isFalse);
      final IncidentCase created = await services.caseRepository.createCase(
        title: 'Test fixture: Application composition',
      );

      expect(database.isOpen, isTrue);
      expect(File(databasePath).existsSync(), isTrue);
      expect(
        (await services.caseRepository.getCaseById(created.id))?.id,
        created.id,
      );

      await services.close();
      expect(database.isOpen, isFalse);
    },
  );
}
