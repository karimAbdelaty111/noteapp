// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// **************************************************************************
// FloorGenerator
// **************************************************************************

abstract class $AppDatabaseBuilderContract {
  /// Adds migrations to the builder.
  $AppDatabaseBuilderContract addMigrations(List<Migration> migrations);

  /// Adds a database [Callback] to the builder.
  $AppDatabaseBuilderContract addCallback(Callback callback);

  /// Creates the database and initializes it.
  Future<AppDatabase> build();
}

// ignore: avoid_classes_with_only_static_members
class $FloorAppDatabase {
  /// Creates a database builder for a persistent database.
  /// Once a database is built, you should keep a reference to it and re-use it.
  static $AppDatabaseBuilderContract databaseBuilder(String name) =>
      _$AppDatabaseBuilder(name);

  /// Creates a database builder for an in memory database.
  /// Information stored in an in memory database disappears when the process is killed.
  /// Once a database is built, you should keep a reference to it and re-use it.
  static $AppDatabaseBuilderContract inMemoryDatabaseBuilder() =>
      _$AppDatabaseBuilder(null);
}

class _$AppDatabaseBuilder implements $AppDatabaseBuilderContract {
  _$AppDatabaseBuilder(this.name);

  final String? name;

  final List<Migration> _migrations = [];

  Callback? _callback;

  @override
  $AppDatabaseBuilderContract addMigrations(List<Migration> migrations) {
    _migrations.addAll(migrations);
    return this;
  }

  @override
  $AppDatabaseBuilderContract addCallback(Callback callback) {
    _callback = callback;
    return this;
  }

  @override
  Future<AppDatabase> build() async {
    final path = name != null
        ? await sqfliteDatabaseFactory.getDatabasePath(name!)
        : ':memory:';
    final database = _$AppDatabase();
    database.database = await database.open(
      path,
      _migrations,
      _callback,
    );
    return database;
  }
}

class _$AppDatabase extends AppDatabase {
  _$AppDatabase([StreamController<String>? listener]) {
    changeListener = listener ?? StreamController<String>.broadcast();
  }

  NoteDao? _noteDaoInstance;

  Future<sqflite.Database> open(
    String path,
    List<Migration> migrations, [
    Callback? callback,
  ]) async {
    final databaseOptions = sqflite.OpenDatabaseOptions(
      version: 2,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
        await callback?.onConfigure?.call(database);
      },
      onOpen: (database) async {
        await callback?.onOpen?.call(database);
      },
      onUpgrade: (database, startVersion, endVersion) async {
        await MigrationAdapter.runMigrations(
            database, startVersion, endVersion, migrations);

        await callback?.onUpgrade?.call(database, startVersion, endVersion);
      },
      onCreate: (database, version) async {
        await database.execute(
            'CREATE TABLE IF NOT EXISTS `notes` (`id` INTEGER PRIMARY KEY AUTOINCREMENT, `note_text` TEXT NOT NULL, `latitude` REAL, `longitude` REAL, `location_accuracy` REAL, `place_name` TEXT, `location_captured_at` INTEGER, `created_at` INTEGER NOT NULL, `updated_at` INTEGER NOT NULL)');

        await callback?.onCreate?.call(database, version);
      },
    );
    return sqfliteDatabaseFactory.openDatabase(path, options: databaseOptions);
  }

  @override
  NoteDao get noteDao {
    return _noteDaoInstance ??= _$NoteDao(database, changeListener);
  }
}

class _$NoteDao extends NoteDao {
  _$NoteDao(
    this.database,
    this.changeListener,
  )   : _queryAdapter = QueryAdapter(database),
        _noteInsertionAdapter = InsertionAdapter(
            database,
            'notes',
            (Note item) => <String, Object?>{
                  'id': item.id,
                  'note_text': item.text,
                  'latitude': item.latitude,
                  'longitude': item.longitude,
                  'location_accuracy': item.locationAccuracy,
                  'place_name': item.placeName,
                  'location_captured_at': _nullableDateTimeConverter
                      .encode(item.locationCapturedAt),
                  'created_at': _dateTimeConverter.encode(item.createdAt),
                  'updated_at': _dateTimeConverter.encode(item.updatedAt)
                }),
        _noteUpdateAdapter = UpdateAdapter(
            database,
            'notes',
            ['id'],
            (Note item) => <String, Object?>{
                  'id': item.id,
                  'note_text': item.text,
                  'latitude': item.latitude,
                  'longitude': item.longitude,
                  'location_accuracy': item.locationAccuracy,
                  'place_name': item.placeName,
                  'location_captured_at': _nullableDateTimeConverter
                      .encode(item.locationCapturedAt),
                  'created_at': _dateTimeConverter.encode(item.createdAt),
                  'updated_at': _dateTimeConverter.encode(item.updatedAt)
                });

  final sqflite.DatabaseExecutor database;

  final StreamController<String> changeListener;

  final QueryAdapter _queryAdapter;

  final InsertionAdapter<Note> _noteInsertionAdapter;

  final UpdateAdapter<Note> _noteUpdateAdapter;

  @override
  Future<void> deleteNoteById(int id) async {
    await _queryAdapter
        .queryNoReturn('DELETE FROM notes WHERE id = ?1', arguments: [id]);
  }

  @override
  Future<void> deleteAllNotes() async {
    await _queryAdapter.queryNoReturn('DELETE FROM notes');
  }

  @override
  Future<List<Note>> getAllNotes() async {
    return _queryAdapter.queryList(
        'SELECT * FROM notes ORDER BY updated_at DESC, id DESC',
        mapper: (Map<String, Object?> row) => Note(
            id: row['id'] as int?,
            text: row['note_text'] as String,
            latitude: row['latitude'] as double?,
            longitude: row['longitude'] as double?,
            locationAccuracy: row['location_accuracy'] as double?,
            placeName: row['place_name'] as String?,
            locationCapturedAt: _nullableDateTimeConverter
                .decode(row['location_captured_at'] as int?),
            createdAt: _dateTimeConverter.decode(row['created_at'] as int),
            updatedAt: _dateTimeConverter.decode(row['updated_at'] as int)));
  }

  @override
  Future<Note?> getNoteById(int id) async {
    return _queryAdapter.query('SELECT * FROM notes WHERE id = ?1',
        mapper: (Map<String, Object?> row) => Note(
            id: row['id'] as int?,
            text: row['note_text'] as String,
            latitude: row['latitude'] as double?,
            longitude: row['longitude'] as double?,
            locationAccuracy: row['location_accuracy'] as double?,
            placeName: row['place_name'] as String?,
            locationCapturedAt: _nullableDateTimeConverter
                .decode(row['location_captured_at'] as int?),
            createdAt: _dateTimeConverter.decode(row['created_at'] as int),
            updatedAt: _dateTimeConverter.decode(row['updated_at'] as int)),
        arguments: [id]);
  }

  @override
  Future<int?> countNotes() async {
    return _queryAdapter.query('SELECT COUNT(*) FROM notes',
        mapper: (Map<String, Object?> row) => row.values.first as int);
  }

  @override
  Future<int?> countNotesWithId(int id) async {
    return _queryAdapter.query('SELECT COUNT(*) FROM notes WHERE id = ?1',
        mapper: (Map<String, Object?> row) => row.values.first as int,
        arguments: [id]);
  }

  @override
  Future<int> insertNote(Note note) {
    return _noteInsertionAdapter.insertAndReturnId(
        note, OnConflictStrategy.abort);
  }

  @override
  Future<int> updateNote(Note note) {
    return _noteUpdateAdapter.updateAndReturnChangedRows(
        note, OnConflictStrategy.abort);
  }
}

// ignore_for_file: unused_element
final _dateTimeConverter = DateTimeConverter();
final _nullableDateTimeConverter = NullableDateTimeConverter();
