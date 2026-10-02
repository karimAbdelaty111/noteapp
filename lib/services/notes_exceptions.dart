import '../database/entities/note.dart';

/// Raised when the note text is empty or only whitespace.
class NoteValidationException implements Exception {
  const NoteValidationException(this.message);

  final String message;

  @override
  String toString() => 'NoteValidationException: $message';
}

/// Raised when an update targets a note that is not in the database anymore.
class NoteNotFoundException implements Exception {
  const NoteNotFoundException([this.message = 'This note no longer exists.']);

  final String message;

  @override
  String toString() => 'NoteNotFoundException: $message';
}

/// Raised when SQLite itself fails (locked file, disk error, ...).
class NoteDatabaseException implements Exception {
  const NoteDatabaseException(this.message);

  final String message;

  @override
  String toString() => 'NoteDatabaseException: $message';
}

/// Outcome of adding, updating **or restoring** a note.
class NoteSaveResult {
  const NoteSaveResult({required this.note, this.warning});

  final Note note;

  /// Set when the user asked for a location but it could not be attached.
  /// The note is still saved — location is optional.
  final String? warning;
}

/// Outcome of deleting a single note.
class NoteDeleteResult {
  const NoteDeleteResult({
    required this.id,
    required this.deleted,
    this.note,
  });

  final int id;

  /// `false` when the note was already gone (no crash, just a message).
  final bool deleted;

  /// The row that was removed, kept in memory **only** so the caller can offer
  /// an Undo. The Undo itself always goes back through the database.
  final Note? note;

  bool get canBeRestored => deleted && note != null;
}

/// Outcome of the shake-to-delete-all business rule.
class DeleteAllResult {
  const DeleteAllResult({required this.deletedCount, this.notes = const []});

  /// `0` means the database was already empty.
  final int deletedCount;

  /// The removed rows, kept so the caller can offer an Undo all.
  final List<Note> notes;

  bool get isEmpty => deletedCount == 0;

  bool get canBeRestored => notes.isNotEmpty;
}

/// Outcome of an Undo (single note or all notes).
class RestoreResult {
  const RestoreResult({required this.restoredCount, this.warning});

  /// How many notes really made it back into SQLite.
  final int restoredCount;

  /// Set when something could not be restored exactly as it was (id conflict,
  /// database failure). The UI shows it so the state is never silently wrong.
  final String? warning;

  bool get isComplete => warning == null;
}