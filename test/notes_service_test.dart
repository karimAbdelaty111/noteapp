import 'package:flutter_test/flutter_test.dart';
import 'package:notetask/database/app_database.dart';
import 'package:notetask/database/entities/note.dart';
import 'package:notetask/services/location_service.dart';
import 'package:notetask/services/notes_exceptions.dart';
import 'package:notetask/services/notes_service.dart';

import 'support/test_support.dart';

void main() {
  late AppDatabase database;
  late FakeLocationService locationService;
  late NotesService service;

  final createdAt = DateTime.utc(2026, 5, 5, 9);

  NotesService serviceWithClock(DateTime Function() clock) {
    return buildNotesService(
      database: database,
      locationService: locationService,
      clock: clock,
    );
  }

  setUp(() async {
    database = await createTestDatabase();
    locationService = fixedLocation();
    service = serviceWithClock(() => createdAt);
  });

  tearDown(() async {
    await database.close();
  });

  Future<Note> singleStoredNote() async {
    final notes = await service.loadNotes();
    expect(notes, hasLength(1));
    return notes.single;
  }

  Future<Note> storedNoteWithText(String text) async {
    final notes = await service.loadNotes();
    return notes.firstWhere((Note note) => note.text == text);
  }

  group('NotesService.normalizeText', () {
    test('trims leading and trailing whitespace', () {
      expect(NotesService.normalizeText('  buy milk \n'), 'buy milk');
    });

    test('normalizes Windows and old Mac line endings', () {
      expect(
        NotesService.normalizeText('a\r\nb\rc\nd'),
        'a\nb\nc\nd',
      );
    });

    test('keeps blank lines inside the note', () {
      expect(NotesService.normalizeText('  a\n\nb  '), 'a\n\nb');
    });
  });

  group('NotesService.validateText', () {
    test('rejects null, empty and whitespace-only text', () {
      expect(NotesService.validateText(null), isNotNull);
      expect(NotesService.validateText(''), isNotNull);
      expect(NotesService.validateText('   \n\t '), isNotNull);
      expect(NotesService.isValidText('   \n\t '), isFalse);
    });

    test('accepts normal text', () {
      expect(NotesService.validateText('a note'), isNull);
      expect(NotesService.isValidText('a note'), isTrue);
    });

    test('rejects a note longer than the maximum', () {
      expect(NotesService.validateText('x' * NotesService.maxLength), isNull);
      expect(
        NotesService.validateText('x' * (NotesService.maxLength + 1)),
        isNotNull,
      );
    });
  });

  group('addNote validation', () {
    test('rejects an empty note', () async {
      expect(
        () => service.addNote(text: ''),
        throwsA(isA<NoteValidationException>()),
      );
      expect(await service.countNotes(), 0);
    });

    test('rejects a whitespace-only note', () async {
      expect(
        () => service.addNote(text: '    \n\t  '),
        throwsA(isA<NoteValidationException>()),
      );
      expect(await service.countNotes(), 0);
    });

    test('rejects an over-long note', () async {
      expect(
        () => service.addNote(text: 'x' * (NotesService.maxLength + 1)),
        throwsA(isA<NoteValidationException>()),
      );
    });
  });

  group('addNote', () {
    test('trims the text and stores the timestamps', () async {
      final result = await service.addNote(text: '   buy milk   ');

      expect(result.note.text, 'buy milk');
      expect(result.note.id, isNotNull);
      expect(result.warning, isNull);

      final stored = await singleStoredNote();
      expect(stored.text, 'buy milk');
      expect(stored.createdAt.toUtc(), createdAt);
      expect(stored.updatedAt.toUtc(), createdAt);
    });

    test('normalizes Windows line endings before saving', () async {
      await service.addNote(text: 'first\r\nsecond\rthird\nfourth');

      expect((await singleStoredNote()).text, 'first\nsecond\nthird\nfourth');
    });

    test('the returned id can be used to fetch the note again', () async {
      final result = await service.addNote(text: 'hello');

      final fetched = await service.findNote(result.note.id!);
      expect(fetched?.text, 'hello');
    });

    test('never touches the location plugin unless it was asked for', () async {
      await service.addNote(text: 'no location please');

      expect(locationService.callCount, 0);
      expect((await singleStoredNote()).hasLocation, isFalse);
    });

    test('attaches the location when it was asked for', () async {
      await service.addNote(text: 'at the office', attachLocation: true);

      final stored = await singleStoredNote();
      expect(locationService.callCount, 1);
      expect(stored.hasLocation, isTrue);
      expect(stored.latitude, closeTo(30.044420, 0.000001));
      expect(stored.longitude, closeTo(31.235712, 0.000001));
      expect(stored.locationAccuracy, closeTo(12, 0.000001));
      expect(stored.locationCapturedAt?.toUtc(), DateTime.utc(2026, 5, 5, 10, 30));
    });
  });

  group('location is optional', () {
    for (final reason in LocationFailureReason.values) {
      test('still saves the note when the location fails with $reason', () async {
        locationService = failingLocation(reason: reason);
        service = serviceWithClock(() => createdAt);

        final result = await service.addNote(text: 'still saved', attachLocation: true);

        expect(result.warning, isNotNull);
        expect(result.note.hasLocation, isFalse);

        final stored = await singleStoredNote();
        expect(stored.text, 'still saved');
        expect(stored.hasLocation, isFalse);
      });
    }

    test('still saves the note when the plugin throws', () async {
      locationService = FakeLocationService(throwsError: true);
      service = serviceWithClock(() => createdAt);

      final result = await service.addNote(text: 'still saved', attachLocation: true);

      expect(result.warning, isNotNull);
      expect((await singleStoredNote()).text, 'still saved');
    });

    test('requireLocation turns a location failure into a validation error', () async {
      locationService = failingLocation();
      service = serviceWithClock(() => createdAt);

      expect(
        () => service.addNote(text: 'saved anyway', attachLocation: true, requireLocation: true),
        throwsA(isA<NoteValidationException>()),
      );
      expect(await service.countNotes(), 0);
    });
  });

  group('loadNotes', () {
    test('returns an empty list when there is nothing', () async {
      expect(await service.loadNotes(), isEmpty);
      expect(await service.countNotes(), 0);
    });

    test('returns the notes newest first', () async {
      await service.addNote(text: 'older');
      service = serviceWithClock(() => createdAt.add(const Duration(hours: 1)));
      await service.addNote(text: 'newer');
      service = serviceWithClock(() => createdAt.add(const Duration(hours: 2)));
      await service.addNote(text: 'newest');

      final texts = (await service.loadNotes()).map((Note note) => note.text);
      expect(texts, <String>['newest', 'newer', 'older']);
    });

    test('findNote returns null for an unknown id', () async {
      expect(await service.findNote(12345), isNull);
    });
  });

  group('updateNote', () {
    test('rejects a note without a database id', () async {
      final unsaved = Note(
        text: 'x',
        createdAt: createdAt,
        updatedAt: createdAt,
      );

      expect(
        () => service.updateNote(note: unsaved, text: 'x'),
        throwsA(isA<NoteValidationException>()),
      );
    });

    test('rejects text that is empty after trimming', () async {
      final note = (await service.addNote(text: 'keep me')).note;

      expect(
        () => service.updateNote(note: note, text: '   '),
        throwsA(isA<NoteValidationException>()),
      );
      expect((await singleStoredNote()).text, 'keep me');
    });

    test('trims the new text', () async {
      final note = (await service.addNote(text: 'before')).note;

      await service.updateNote(note: note, text: '   after\r\n  ');

      expect((await singleStoredNote()).text, 'after');
    });

    test('throws NoteNotFoundException when the row disappeared', () async {
      final note = (await service.addNote(text: 'before')).note;
      await service.deleteNote(note.id!);

      expect(
        () => service.updateNote(note: note, text: 'after'),
        throwsA(isA<NoteNotFoundException>()),
      );
    });

    test('moves updatedAt forward and keeps createdAt', () async {
      final note = (await service.addNote(text: 'before')).note;

      service = serviceWithClock(() => createdAt.add(const Duration(hours: 3)));
      await service.updateNote(note: note, text: 'after');

      final stored = await singleStoredNote();
      expect(stored.text, 'after');
      expect(stored.createdAt.toUtc(), createdAt);
      expect(stored.updatedAt.toUtc(), createdAt.add(const Duration(hours: 3)));
    });

    test('keeps the existing location when no location flag is used', () async {
      final note = (await service.addNote(text: 'first', attachLocation: true)).note;

      await service.updateNote(note: note, text: 'second');

      final stored = await singleStoredNote();
      expect(stored.text, 'second');
      expect(stored.hasLocation, isTrue);
      expect(locationService.callCount, 1, reason: 'no second location request');
    });

    test('can add a location to a note that had none', () async {
      final note = (await service.addNote(text: 'first')).note;

      await service.updateNote(note: note, text: 'first', attachLocation: true);

      expect((await singleStoredNote()).hasLocation, isTrue);
    });

    test('removeLocation clears the stored coordinates', () async {
      final note = (await service.addNote(text: 'first', attachLocation: true)).note;

      await service.updateNote(note: note, text: 'first', removeLocation: true);

      final stored = await singleStoredNote();
      expect(stored.hasLocation, isFalse);
      expect(stored.location, isNull);
      expect(stored.locationAccuracy, isNull);
    });

    test('keeps the old coordinates when a refresh fails', () async {
      final note = (await service.addNote(text: 'first', attachLocation: true)).note;
      final latitude = (await service.findNote(note.id!))!.latitude;

      locationService = failingLocation();
      service = serviceWithClock(() => createdAt.add(const Duration(hours: 1)));
      final result = await service.updateNote(note: note, text: 'second', attachLocation: true);

      expect(result.warning, isNotNull);
      final stored = await singleStoredNote();
      expect(stored.hasLocation, isTrue);
      expect(stored.latitude, latitude);
    });

    test('a failed refresh with requireLocation leaves the note untouched', () async {
      final note = (await service.addNote(text: 'first', attachLocation: true)).note;

      locationService = failingLocation();
      service = serviceWithClock(() => createdAt.add(const Duration(hours: 1)));

      expect(
        () => service.updateNote(
          note: note,
          text: 'second',
          attachLocation: true,
          requireLocation: true,
        ),
        throwsA(isA<NoteValidationException>()),
      );
      expect((await singleStoredNote()).text, 'first');
    });
  });

  group('deleteNote', () {
    test('reports whether a row was really removed', () async {
      final note = (await service.addNote(text: 'bye')).note;

      final result = await service.deleteNote(note.id!);

      expect(result.deleted, isTrue);
      expect(result.id, note.id);
      expect(await service.countNotes(), 0);
    });

    test('is a safe no-op for an unknown id', () async {
      final result = await service.deleteNote(9999);

      expect(result.deleted, isFalse);
      expect(result.id, 9999);
    });

    test('leaves the other notes alone', () async {
      final first = (await service.addNote(text: 'first')).note;
      await service.addNote(text: 'second');

      await service.deleteNote(first.id!);

      expect(await service.countNotes(), 1);
      expect((await service.loadNotes()).single.text, 'second');
    });
  });

  group('deleteAllNotes', () {
    test('is a safe no-op on an empty database', () async {
      final result = await service.deleteAllNotes();

      expect(result.deletedCount, 0);
      expect(await service.loadNotes(), isEmpty);
    });

    test('removes every note and reports how many', () async {
      await service.addNote(text: 'a');
      await service.addNote(text: 'b');
      await service.addNote(text: 'c');

      final result = await service.deleteAllNotes();

      expect(result.deletedCount, 3);
      expect(await service.loadNotes(), isEmpty);
      expect(await service.countNotes(), 0);
    });

    test('removes notes that carry a location too', () async {
      await service.addNote(text: 'a', attachLocation: true);
      await service.addNote(text: 'b');

      await service.deleteAllNotes();

      expect(await service.countNotes(), 0);
    });
  });

  group('database failures', () {
    test('reads report a NoteDatabaseException', () async {
      await database.close();

      await expectLater(service.loadNotes(), throwsA(isA<NoteDatabaseException>()));
      await expectLater(service.countNotes(), throwsA(isA<NoteDatabaseException>()));
      await expectLater(service.findNote(1), throwsA(isA<NoteDatabaseException>()));
    });

    test('writes report a NoteDatabaseException', () async {
      await database.close();

      await expectLater(
        service.addNote(text: 'after close'),
        throwsA(isA<NoteDatabaseException>()),
      );
      await expectLater(
        service.deleteNote(1),
        throwsA(isA<NoteDatabaseException>()),
      );
      await expectLater(service.deleteAllNotes(), throwsA(isA<NoteDatabaseException>()));
    });

    test('the message is human readable, not a raw driver error', () async {
      await database.close();

      try {
        await service.loadNotes();
        fail('a NoteDatabaseException was expected');
      } on NoteDatabaseException catch (exception) {
        expect(exception.message, contains('database'));
        expect(exception.toString(), isNot(contains('DatabaseException(')));
      }
    });
  });

  group('NoteDeleteResult / DeleteAllResult', () {
    test('carry the values the UI shows', () {
      const deleted = NoteDeleteResult(id: 7, deleted: true);
      const missing = NoteDeleteResult(id: 7, deleted: false);
      const all = DeleteAllResult(deletedCount: 3);

      expect(deleted.deleted, isTrue);
      expect(missing.deleted, isFalse);
      expect(all.deletedCount, 3);
    });
  });

  group('helpers used by the list screen', () {
    test('the list can be rebuilt from loadNotes after a delete', () async {
      await service.addNote(text: 'keep');
      final doomed = (await service.addNote(text: 'doomed')).note;

      await service.deleteNote(doomed.id!);

      final notes = await service.loadNotes();
      expect(notes.map((Note note) => note.text), <String>['keep']);
      expect(await service.findNote(doomed.id!), isNull);
    });

    test('a note stored with a location keeps it across updates', () async {
      final note = (await service.addNote(text: 'located', attachLocation: true)).note;
      final before = await service.findNote(note.id!);

      await service.updateNote(note: before!, text: 'located again');

      final after = await service.findNote(note.id!);
      expect(after!.location, before.location);
      expect(after.location!.coordinates, before.location!.coordinates);
    });

    test('findNote finds the note that was saved last', () async {
      final first = (await service.addNote(text: 'first')).note;
      final second = (await service.addNote(text: 'second')).note;

      expect((await service.findNote(second.id!))!.text, 'second');
      expect((await storedNoteWithText('first')).id, first.id);
    });
  });
}