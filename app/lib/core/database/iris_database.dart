import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'database_constants.dart';
import 'migrations/database_migrations.dart';

typedef DatabaseDirectoryProvider = Future<String> Function();

class IrisDatabase {
  IrisDatabase({
    DatabaseFactory? factory,
    String? databasePath,
    DatabaseDirectoryProvider? databaseDirectoryProvider,
  }) : _factory = factory ?? databaseFactory,
       _databasePath = databasePath,
       _databaseDirectoryProvider =
           databaseDirectoryProvider ?? getDatabasesPath;

  final DatabaseFactory _factory;
  final String? _databasePath;
  final DatabaseDirectoryProvider _databaseDirectoryProvider;

  Database? _database;
  Future<Database>? _opening;

  bool get isOpen => _database?.isOpen ?? false;

  Future<String> resolvePath() async {
    final String? explicitPath = _databasePath;
    if (explicitPath != null) {
      return explicitPath;
    }

    final String databaseDirectory = await _databaseDirectoryProvider();
    if (kDebugMode) {
      debugPrint('IRIS sqflite getDatabasesPath channel responded.');
    }
    return path.join(databaseDirectory, IrisDatabaseConstants.fileName);
  }

  Future<Database> open() async {
    final Database? existing = _database;
    if (existing != null && existing.isOpen) {
      return existing;
    }

    final Future<Database>? opening = _opening;
    if (opening != null) {
      return opening;
    }

    final Future<Database> operation = _openDatabase();
    _opening = operation;
    try {
      final Database database = await operation;
      _database = database;
      return database;
    } finally {
      _opening = null;
    }
  }

  Future<void> close() async {
    Database? database = _database;
    final Future<Database>? opening = _opening;
    if (database == null && opening != null) {
      try {
        database = await opening;
      } on Object {
        return;
      }
    }
    _database = null;
    if (database != null && database.isOpen) {
      await database.close();
    }
  }

  Future<Database> _openDatabase() async {
    try {
      final String resolvedPath = await resolvePath();
      final Database database = await _factory.openDatabase(
        resolvedPath,
        options: OpenDatabaseOptions(
          version: IrisDatabaseConstants.schemaVersion,
          onConfigure: (Database database) async {
            await database.execute('PRAGMA foreign_keys = ON');
          },
          onCreate: (Database database, int version) {
            return migrateDatabase(database, 0, version);
          },
          onUpgrade: migrateDatabase,
          onDowngrade: (Database database, int oldVersion, int newVersion) {
            throw StateError(
              'Database downgrade from $oldVersion to $newVersion is not supported.',
            );
          },
        ),
      );

      try {
        await _verifySchema(database);
      } on Object {
        await database.close();
        rethrow;
      }

      if (kDebugMode) {
        debugPrint(
          'IRIS SQLite initialized: ${path.basename(resolvedPath)}, '
          'schema v${IrisDatabaseConstants.schemaVersion}.',
        );
      }
      return database;
    } on Object catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'IRIS SQLite initialization failed (${error.runtimeType}): $error',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
      rethrow;
    }
  }

  Future<void> _verifySchema(Database database) async {
    final int version = await database.getVersion();
    if (version != IrisDatabaseConstants.schemaVersion) {
      throw StateError(
        'Unexpected IRIS database version $version; expected '
        '${IrisDatabaseConstants.schemaVersion}.',
      );
    }

    final List<Map<String, Object?>> tables = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      <Object?>[
        IrisDatabaseConstants.casesTable,
        IrisDatabaseConstants.evidenceTable,
        IrisDatabaseConstants.evidenceQualityTable,
        IrisDatabaseConstants.evidenceClassificationTable,
        IrisDatabaseConstants.evidenceDetectionAnalysesTable,
        IrisDatabaseConstants.evidenceDetectionsTable,
        IrisDatabaseConstants.evidenceSegmentationAnalysesTable,
        IrisDatabaseConstants.evidenceSegmentationMasksTable,
        IrisDatabaseConstants.evidenceDepthAnalysesTable,
        IrisDatabaseConstants.evidenceGeometryAnalysesTable,
        IrisDatabaseConstants.multiViewPairAnalysesTable,
        IrisDatabaseConstants.caseLocationsTable,
        IrisDatabaseConstants.roadContextsTable,
        IrisDatabaseConstants.evidenceWorldAlignmentsTable,
        IrisDatabaseConstants.environmentContextsTable,
        IrisDatabaseConstants.scenarioObservationsTable,
        IrisDatabaseConstants.scenarioAnalysesTable,
      ],
    );
    if (tables.length != 17) {
      throw StateError('IRIS database schema is missing required tables.');
    }
  }
}
