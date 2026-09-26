import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'database_constants.dart';
import 'migrations/database_migrations.dart';

class IrisDatabase {
  IrisDatabase({DatabaseFactory? factory, String? databasePath})
    : _factory = factory ?? databaseFactory,
      _databasePath = databasePath;

  final DatabaseFactory _factory;
  final String? _databasePath;

  Database? _database;
  Future<Database>? _opening;

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
    final Database? database = _database;
    _database = null;
    if (database != null && database.isOpen) {
      await database.close();
    }
  }

  Future<Database> _openDatabase() async {
    final String resolvedPath =
        _databasePath ??
        path.join(await getDatabasesPath(), IrisDatabaseConstants.fileName);

    return _factory.openDatabase(
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
  }
}
