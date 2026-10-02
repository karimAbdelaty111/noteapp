import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import '../database/dao/note_dao.dart';
import '../database/entities/note.dart';
import 'location_service.dart';
import 'notes_exceptions.dart';

/// Repository + business rules for notes.
///
/// Screens call these methods only; they never see the DAO, the SQL or the
/// `geolocator` plugin. Every method either returns a value or throws one of
/// the typed exceptions in `notes_exceptions.dart`, so the UI can show a
/// friendly message instead of crashing.
class NotesService {
  NotesService({
    required this.noteDao,
    required this.locationService,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final NoteDao noteDao;
  final LocationService locationService;
  final DateTime Function() _clock;

  /// Longest note the app accepts. Keeps a single note from being unusable in
  /// the list, and matches what the input field enforces.
  static const int maxLength = 4000;

  // ---------------------------------------------------------------------
  // Business rules (pure functions - easy to unit test)
  // ---------------------------------------------------------------------

  /// Removes the whitespace that is not part of the note itself:
  /// Windows line endings and every leading/trailing space, tab or newline.
  static String normalizeText(String raw) {
    return raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  }

  /// Business rules 1 & 2: an empty or whitespace-only note is invalid.
  static bool isValidText(String raw) => normalizeText(raw).isNotEmpty;

  static String? validateText(String? raw) {
    if (raw == null) return 'Please enter a note.';
    if (!isValidText(raw)) return 'A note cannot be empty.';
    if (normalizeText(raw).length > maxLength) {
      return 'A note can be at most $maxLength characters.';
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------

  /// All notes, newest first. Database failures become [NoteDatabaseException].
  Future<List<Note>> loadNotes() async {
    try {
      return await noteDao.getAllNotes();
    } on sqflite.DatabaseException catch (error) {
      throw NoteDatabaseException(_databaseMessage(error));
    }
  }

  /// A single note, or `null` when it does not exist.
  Future<Note?> findNote(int id) async {
    try {
      return await noteDao.getNoteById(id);
    } on sqflite.DatabaseException catch (error) {
      throw NoteDatabaseException(_databaseMessage(error));
    }
  }

  /// How many notes are stored (used by the delete-all business rule).
  Future<int> countNotes() async {
    try {
      return await noteDao.countNotes() ?? 0;
    } on sqflite.DatabaseException catch (error) {
      throw NoteDatabaseException(_databaseMessage(error));
    }
  }

  // ---------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------

  /// Validates, trims, optionally attaches a location and stores a new note.
  ///
  /// Location is optional: when [attachLocation] is `true` but the location
  /// cannot be read, the note is still saved and the reason is returned in
  /// [NoteSaveResult.warning]. Set [requireLocation] to `true` to make the
  /// location mandatory — then a failure throws instead.
  Future<NoteSaveResult> addNote({
    required String text,
    bool attachLocation = false,
    bool requireLocation = false,
  }) async {
    final validationError = validateText(text);
    if (validationError != null) {
      throw NoteValidationException(validationError);
    }
    final cleanText = normalizeText(text);

    String? warning;
    NoteLocation? location;
    if (attachLocation) {
      final result = await _safeLocation();
      if (result.isSuccess) {
        location = result.location;
      } else {
        if (requireLocation) {
          throw NoteValidationException(
            result.message ?? 'Could not attach a location to the note.',
          );
        }
        warning = result.message;
      }
    }

    final now = _clock();
    final note = Note(
      text: cleanText,
      latitude: location?.latitude,
      longitude: location?.longitude,
      locationAccuracy: location?.accuracy,
      placeName: location?.placeName,
      locationCapturedAt: location?.capturedAt ?? (location != null ? now : null),
      createdAt: now,
      updatedAt: now,
    );

    try {
      final id = await noteDao.insertNote(note);
      return NoteSaveResult(note: note.copyWith(id: id), warning: warning);
    } on sqflite.DatabaseException catch (error) {
      throw NoteDatabaseException(_databaseMessage(error));
    }
  }

  /// Updates an existing note (business rules 3, 4 and 5).
  ///
  /// [attachLocation] refreshes the coordinates; [removeLocation] clears them;
  /// when both are `false` the note keeps the location it already has.
  Future<NoteSaveResult> updateNote({
    required Note note,
    required String text,
    bool attachLocation = false,
    bool removeLocation = false,
    bool requireLocation = false,
  }) async {
    final id = note.id;
    if (id == null) {
      throw const NoteValidationException('This note has no database id.');
    }

    final validationError = validateText(text);
    if (validationError != null) {
      throw NoteValidationException(validationError);
    }
    final cleanText = normalizeText(text);

    String? warning;
    NoteLocation? location = note.location;

    if (removeLocation) {
      location = null;
    } else if (attachLocation) {
      final result = await _safeLocation();
      if (result.isSuccess) {
        location = result.location;
      } else {
        if (requireLocation) {
          throw NoteValidationException(
            result.message ?? 'Could not attach a location to the note.',
          );
        }
        warning = result.message;
      }
    }

    final updated = note.copyWith(
      text: cleanText,
      latitude: location?.latitude,
      longitude: location?.longitude,
      locationAccuracy: location?.accuracy,
      placeName: location?.placeName,
      locationCapturedAt: location?.capturedAt,
      clearLocation: location == null,
      updatedAt: _clock(),
    );

    try {
      final affectedRows = await noteDao.updateNote(updated);
      if (affectedRows == 0) {
        throw const NoteNotFoundException(
          'This note was deleted already, it cannot be updated.',
        );
      }
      return NoteSaveResult(note: updated, warning: warning);
    } on sqflite.DatabaseException catch (error) {
      throw NoteDatabaseException(_databaseMessage(error));
    }
  }

  /// Deletes one note. Deleting an unknown id is safe (business rule 6).
  ///
  /// The note is looked up first so the result can honestly report whether a
  /// row was really removed, on every platform, and so the UI can offer an Undo.
  Future<NoteDeleteResult> deleteNote(int id) async {
    try {
      final existing = await noteDao.getNoteById(id);
      if (existing == null) {
        return NoteDeleteResult(id: id, deleted: false);
      }
      await noteDao.deleteNoteById(id);
      return NoteDeleteResult(id: id, deleted: true, note: existing);
    } on sqflite.DatabaseException catch (error) {
      throw NoteDatabaseException(_databaseMessage(error));
    }
  }

  /// Puts a deleted note back into the database (the Undo action).
  ///
  /// The original id is reused when it is still free, so the note comes back
  /// *exactly* as it was — text, location, place name and both timestamps.
  /// When the id was taken meanwhile (another note reused it), the note is
  /// restored under a new id instead of overwriting the other row, and a
  /// warning explains what happened.
  Future<NoteSaveResult> restoreNote(Note note) async {
    if (!note.hasLocation && note.text.trim().isEmpty) {
      throw const NoteValidationException('There is nothing to restore.');
    }

    final originalId = note.id;
    final idInUse = originalId != null
        ? (await noteDao.countNotesWithId(originalId) ?? 0) > 0
        : false;

    final toInsert = idInUse ? note.copyWith(clearId: true) : note;

    try {
      final newId = await noteDao.insertNote(toInsert);
      return NoteSaveResult(
        note: toInsert.copyWith(id: newId),
        warning: idInUse
            ? 'The note was restored, but it received a new id because the '
                  'original one was taken.'
            : null,
      );
    } on sqflite.DatabaseException catch (error) {
      throw NoteDatabaseException(_databaseMessage(error));
    }
  }

  /// Business rule behind the shake gesture: deletes every note at once.
  ///
  /// Calling it on an empty database is safe and simply reports `0`
  /// (business rule 7). The UI is responsible for asking the user first.
  Future<DeleteAllResult> deleteAllNotes() async {
    try {
      final storedNotes = await noteDao.getAllNotes();
      if (storedNotes.isEmpty) {
        return const DeleteAllResult(deletedCount: 0);
      }
      await noteDao.deleteAllNotes();
      return DeleteAllResult(deletedCount: storedNotes.length, notes: storedNotes);
    } on sqflite.DatabaseException catch (error) {
      throw NoteDatabaseException(_databaseMessage(error));
    }
  }

  /// Puts every note of a "delete all" back into the database (Undo all).
  ///
  /// The notes are restored oldest id first, so the original ordering of the
  /// `AUTOINCREMENT` sequence is kept as closely as possible. A note whose id
  /// is already taken is restored under a new id and reported in the warning,
  /// so a partial restore can never silently corrupt the data.
  Future<RestoreResult> restoreNotes(List<Note> notes) async {
    if (notes.isEmpty) {
      return const RestoreResult(restoredCount: 0);
    }

    var restoredCount = 0;
    final warnings = <String>[];

    final ordered = List<Note>.of(notes)
      ..sort((Note a, Note b) => (a.id ?? 0).compareTo(b.id ?? 0));

    for (final note in ordered) {
      try {
        final result = await restoreNote(note);
        restoredCount++;
        final warning = result.warning;
        if (warning != null) warnings.add(warning);
      } on NoteValidationException catch (error) {
        warnings.add(error.message);
      } on NoteDatabaseException catch (error) {
        warnings.add(error.message);
        break;
      }
    }

    return RestoreResult(
      restoredCount: restoredCount,
      warning: warnings.isEmpty
          ? null
          : 'Only $restoredCount of ${notes.length} notes could be restored.',
    );
  }

  // ---------------------------------------------------------------------
  // Location
  // ---------------------------------------------------------------------

  /// Reads the current location **without saving anything**.
  ///
  /// The add screen uses it to show the resolved place name while the user is
  /// still writing. It never throws: a failure comes back as a
  /// [LocationResult] the UI can explain in one line.
  Future<LocationResult> previewLocation() => _safeLocation();

  /// Wraps the location call so a plugin failure can never escape as a crash.
  Future<LocationResult> _safeLocation() async {
    try {
      return await locationService.getCurrentLocation();
    } on Object catch (error, stackTrace) {
      debugPrint('Location request failed unexpectedly: $error\n$stackTrace');
      return LocationResult.failure(
        LocationFailureReason.unknown,
        'Could not read the location. The note was saved without a location.',
      );
    }
  }

  String _databaseMessage(sqflite.DatabaseException error) {
    if (error.isDatabaseClosedError()) {
      return 'The database is closed. Please restart the app.';
    }
    if (error.isNoSuchTableError()) {
      return 'The notes table is missing. Please restart the app.';
    }
    return 'Could not read or write the notes database.';
  }
}
