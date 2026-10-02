import 'package:floor/floor.dart';

import '../entities/note.dart';

/// All SQL for the `notes` table lives here.
/// Screens never write SQL, and widgets never talk to the DAO directly.
///
/// Note: the annotation is written as `@dao` (the `const dao` marker object
/// exported by Floor) instead of `@Dao`. Both describe the same annotation, but
/// the constant form is the one Floor itself uses everywhere.
@dao
abstract class NoteDao {
  /// Inserts a new note and returns the generated row id.
  ///
  /// [OnConflictStrategy.abort] means an accidental double insert with the same
  /// primary key fails loudly instead of silently overwriting a row.
  @Insert(onConflict: OnConflictStrategy.abort)
  Future<int> insertNote(Note note);

  /// Updates an existing note and returns the number of affected rows.
  ///
  /// `0` means the note no longer exists in the database, which the service
  /// layer converts into a friendly message instead of an exception.
  @Update()
  Future<int> updateNote(Note note);

  /// Deletes the note with [id]. Deleting an unknown id is a safe no-op, which
  /// is why this returns `Future<void>`: the caller decides what "deleted"
  /// means by checking the note first (see `NotesService.deleteNote`).
  @Query('DELETE FROM notes WHERE id = :id')
  Future<void> deleteNoteById(int id);

  /// Deletes every note. Safe on an already empty table.
  @Query('DELETE FROM notes')
  Future<void> deleteAllNotes();

  /// All notes, most recently updated first.
  @Query('SELECT * FROM notes ORDER BY updated_at DESC, id DESC')
  Future<List<Note>> getAllNotes();

  /// A single note, or `null` when the id does not exist.
  @Query('SELECT * FROM notes WHERE id = :id')
  Future<Note?> getNoteById(int id);

  /// Number of stored notes.
  ///
  /// Floor requires a `@Query` that returns a single column to be nullable,
  /// hence `Future<int?>` — `COUNT(*)` itself always returns a value.
  @Query('SELECT COUNT(*) FROM notes')
  Future<int?> countNotes();

  /// Whether the primary key [id] is already taken.
  ///
  /// The undo flow uses it to decide whether a deleted note can go back with
  /// its original id or has to be re-inserted with a fresh one.
  @Query('SELECT COUNT(*) FROM notes WHERE id = :id')
  Future<int?> countNotesWithId(int id);
}
