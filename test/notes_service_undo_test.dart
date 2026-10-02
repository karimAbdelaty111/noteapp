import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notetask/database/app_database.dart';
import 'package:notetask/database/entities/note.dart';
import 'package:notetask/services/location_service.dart';
import 'package:notetask/services/notes_exceptions.dart';
import 'package:notetask/services/notes_service.dart';

import 'support/test_support.dart';

/// The undo/delete-all contract used by the list screen:
/// delete returns the row, restore puts the very same row back with its id.
void main() {
  late AppDatabase database;
  late NotesService notesService;

  setUp(() async {
    database = await createTestDatabase();
    notesService = buildNotesService(
      database: database,
      locationService: fixedLocation(),
    );
  });

  tearDown(() async {
    await database.close();
  });

  Future<int> storeNote(String text, {bool withLocation = false}) async {
    final result = await notesService.addNote(
      text: text,
      attachLocation: withLocation,
    );
    return result.note.id!;
  }

  group('deleteNote', () {
    test('returns the deleted note so it can be restored', () async {
      final id = await storeNote('buy milk', withLocation: true);

      final result = await notesService.deleteNote(id);

      expect(result.id, id);
      expect(result.deleted, isTrue);
      expect(result.note, isNotNull);
      expect(result.note!.text, 'buy milk');
      expect(result.note!.location!.placeName, 'Dokki, Giza, Egypt');
      expect(await notesService.countNotes(), 0);
    });

    test('reports failure for an unknown id instead of throwing', () async {
      final result = await notesService.deleteNote(4242);

      expect(result.deleted, isFalse);
      expect(result.note, isNull);
    });

    test('handles an impossible id gracefully', () async {
      await storeNote('still here');

      final result = await notesService.deleteNote(-1);

      expect(result.deleted, isFalse);
      expect(result.note, isNull);
      expect(await notesService.countNotes(), 1);
    });
  });

  group('restoreNote', () {
    test('brings the note back with the same id and content', () async {
      final id = await storeNote('restore me', withLocation: true);
      final deleted = (await notesService.deleteNote(id)).note!;

      final result = await notesService.restoreNote(deleted);

      expect(result.warning, isNull);
      expect(result.note.id, id, reason: 'undo must restore the exact row');
      expect(result.note.text, 'restore me');
      expect(result.note.location!.latitude, closeTo(30.044420, 0.0001));
      expect(result.note.location!.placeName, 'Dokki, Giza, Egypt');

      final reloaded = await notesService.findNote(id);
      expect(reloaded, isNotNull);
      expect(reloaded!.text, 'restore me');
      expect(await notesService.countNotes(), 1);
    });

    test('falls back to a new id when the old one is taken again', () async {
      final id = await storeNote('original');
      final deleted = (await notesService.deleteNote(id)).note!;
      // Something else claims the same id while the snackbar is on screen.
      await notesService.noteDao.insertNote(
        Note(
          id: id,
          text: 'squatter',
          createdAt: DateTime.utc(2026, 5, 5, 9),
          updatedAt: DateTime.utc(2026, 5, 5, 9),
        ),
      );

      final result = await notesService.restoreNote(deleted);

      expect(result.note.id, isNot(id));
      expect(result.note.text, 'original');
      expect(result.warning, isNotNull);
      expect(await notesService.countNotes(), 2);
      expect((await notesService.findNote(id))!.text, 'squatter');
    });

    test('refuses to restore empty text', () async {
      final id = await storeNote('temporary');
      final deleted = (await notesService.deleteNote(id)).note!;
      final blank = deleted.copyWith(clearId: true, text: '   ');

      expect(
        () => notesService.restoreNote(blank),
        throwsA(isA<NoteValidationException>()),
      );
    });

    test('a round trip keeps the note untouched in every field', () async {
      final id = await storeNote('everything', withLocation: true);
      final before = (await notesService.findNote(id))!;

      final deleted = (await notesService.deleteNote(id)).note!;
      await notesService.restoreNote(deleted);

      final after = (await notesService.findNote(id))!;
      expect(after.text, before.text);
      expect(after.createdAt, before.createdAt);
      expect(after.location, before.location);
    });
  });

  group('deleteAllNotes', () {
    test('empties the table and returns every deleted row', () async {
      await storeNote('one');
      await storeNote('two');
      final located = await storeNote('three', withLocation: true);

      final result = await notesService.deleteAllNotes();

      expect(result.deletedCount, 3);
      expect(result.notes.map((note) => note.text), containsAll(['one', 'two', 'three']));
      expect(await notesService.countNotes(), 0);

      final deletedWithLocation =
          result.notes.firstWhere((note) => note.text == 'three');
      expect(deletedWithLocation.id, located);
      expect(deletedWithLocation.location!.placeName, 'Dokki, Giza, Egypt');
    });

    test('is a no-op on an empty database', () async {
      final result = await notesService.deleteAllNotes();

      expect(result.deletedCount, 0);
      expect(result.notes, isEmpty);
    });

    test('UNDO ALL restores every note', () async {
      await storeNote('one');
      await storeNote('two', withLocation: true);
      await storeNote('three');

      final deleted = await notesService.deleteAllNotes();
      final restored = await notesService.restoreNotes(deleted.notes);

      expect(restored.restoredCount, 3);
      expect(restored.warning, isNull);

      final notes = await notesService.loadNotes();
      expect(notes.map((note) => note.text), containsAll(['one', 'two', 'three']));
      expect(notes.firstWhere((note) => note.text == 'two').location!.placeName,
          'Dokki, Giza, Egypt');
    });

    test('restoring an empty list does nothing', () async {
      await storeNote('one');

      final restored = await notesService.restoreNotes(const []);

      expect(restored.restoredCount, 0);
      expect(await notesService.countNotes(), 1);
    });

    test('a partial conflict still restores everything possible', () async {
      await storeNote('one');
      await storeNote('two');
      final deleted = await notesService.deleteAllNotes();
      expect(deleted.notes.map((note) => note.text), ['two', 'one']);

      // One of the two rows is restored by hand, so its id is taken again.
      await notesService.restoreNote(
        deleted.notes.firstWhere((note) => note.text == 'two'),
      );

      final restored = await notesService.restoreNotes(deleted.notes);

      expect(restored.restoredCount, 2);
      expect(restored.warning, isNotNull, reason: 'one row needed a new id');
      expect(await notesService.countNotes(), 3);
      expect(
        (await notesService.loadNotes()).map((note) => note.text),
        containsAll(['one', 'two']),
      );
    });
  });

  group('place name persistence', () {
    test('the readable name survives a database round trip', () async {
      final id = await storeNote('named place', withLocation: true);

      final stored = (await notesService.findNote(id))!;

      expect(stored.location!.placeName, 'Dokki, Giza, Egypt');
      expect(stored.placeName, 'Dokki, Giza, Egypt');
      expect(stored.location!.title, 'Dokki, Giza, Egypt');
      expect(stored.location!.hasPlaceName, isTrue);
    });

    test('a location without a name falls back to coordinates', () async {
      notesService = buildNotesService(
        database: database,
        locationService: fixedLocation(placeName: null),
      );

      final id = await storeNote('no name', withLocation: true);
      final stored = (await notesService.findNote(id))!;

      expect(stored.location!.hasPlaceName, isFalse);
      expect(stored.location!.title, 'Location available');
      expect(stored.location!.displayText, contains('30.04'));
      expect(stored.placeName, isNull);
    });

    test('a bare location can be stored directly', () async {
      await notesService.noteDao.insertNote(
        Note(
          text: 'legacy row',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
          latitude: 1,
          longitude: 2,
        ),
      );

      final notes = await notesService.loadNotes();

      expect(notes.single.location!.title, 'Location available');
      expect(notes.single.location!.displayText, '1.000000, 2.000000');
    });
  });

  group('file backed database', () {
    test('notes and place names survive closing and reopening', () async {
      final path = '${Directory.systemTemp.path}/notetask_undo_test.db';
      final file = File(path);
      if (file.existsSync()) file.deleteSync();

      final first = await openNotesDatabase(filePath: path);
      final firstService = buildNotesService(
        database: first,
        locationService: fixedLocation(),
      );
      final id = (await firstService.addNote(
        text: 'survives a restart',
        attachLocation: true,
      )).note.id!;
      await first.close();

      final second = await openNotesDatabase(filePath: path);
      final secondService = buildNotesService(
        database: second,
        locationService: fixedLocation(),
      );
      final reopened = await secondService.findNote(id);
      await second.close();

      expect(reopened, isNotNull);
      expect(reopened!.text, 'survives a restart');
      expect(reopened.placeName, 'Dokki, Giza, Egypt');

      if (file.existsSync()) file.deleteSync();
    });
  });

  group('location failure', () {
    test('a failing plugin still stores the note', () async {
      notesService = buildNotesService(
        database: database,
        locationService: FakeLocationService(throwsError: true),
      );

      final result = await notesService.addNote(
        text: 'no location',
        attachLocation: true,
      );

      expect(result.note.hasLocation, isFalse);
      expect(result.warning, isNotNull);
      expect(result.warning, contains('location'));
    });

    test('previewLocation surfaces the failure message', () async {
      notesService = buildNotesService(
        database: database,
        locationService: failingLocation(
          reason: LocationFailureReason.serviceDisabled,
          message: 'Turn location on.',
        ),
      );

      final preview = await notesService.previewLocation();

      expect(preview.isSuccess, isFalse);
      expect(preview.location, isNull);
      expect(preview.message, 'Turn location on.');
      expect(preview.failureReason, LocationFailureReason.serviceDisabled);
    });
  });
}