import 'package:flutter_test/flutter_test.dart';
import 'package:notetask/database/app_database.dart';
import 'package:notetask/database/entities/note.dart';

import 'support/test_support.dart';

void main() {
  late AppDatabase database;

  final fixedTime = DateTime.utc(2026, 3, 4, 5, 6, 7);

  setUp(() async {
    database = await createTestDatabase();
  });

  tearDown(() async {
    await database.close();
  });

  Note note(String text, {int? id, NoteLocation? location}) {
    return Note(
      id: id,
      text: text,
      latitude: location?.latitude,
      longitude: location?.longitude,
      locationAccuracy: location?.accuracy,
      locationCapturedAt: location?.capturedAt,
      createdAt: fixedTime,
      updatedAt: fixedTime,
    );
  }

  group('NoteDao', () {
    test('starts empty', () async {
      expect(await database.noteDao.getAllNotes(), isEmpty);
      expect(await database.noteDao.countNotes(), 0);
    });

    test('insert generates a safe, unique id', () async {
      final first = await database.noteDao.insertNote(note('first'));
      final second = await database.noteDao.insertNote(note('second'));

      expect(first, greaterThan(0));
      expect(second, greaterThan(first));

      final notes = await database.noteDao.getAllNotes();
      expect(notes.map((Note n) => n.id), containsAll(<int>[first, second]));
    });

    test('inserting the same explicit id twice is rejected', () async {
      await database.noteDao.insertNote(note('first', id: 42));

      expect(
        () => database.noteDao.insertNote(note('duplicate', id: 42)),
        throwsA(isA<Exception>()),
      );
    });

    test('stores and reads back the note text', () async {
      final id = await database.noteDao.insertNote(note('buy milk'));

      final stored = await database.noteDao.getNoteById(id);
      expect(stored?.text, 'buy milk');
      expect(stored?.createdAt.toUtc(), fixedTime);
      expect(stored?.updatedAt.toUtc(), fixedTime);
    });

    test('location columns stay NULL when there is no location', () async {
      final id = await database.noteDao.insertNote(note('no location'));

      final stored = await database.noteDao.getNoteById(id);
      expect(stored?.hasLocation, isFalse);
      expect(stored?.location, isNull);
      expect(stored?.latitude, isNull);
      expect(stored?.longitude, isNull);
      expect(stored?.locationCapturedAt, isNull);
    });

    test('stores and reads back latitude/longitude as REAL columns', () async {
      final location = NoteLocation(
        latitude: 30.044420,
        longitude: 31.235712,
        accuracy: 8.5,
        capturedAt: DateTime.utc(2026, 2, 3, 4, 5),
      );
      final id = await database.noteDao.insertNote(note('at work', location: location));

      final stored = await database.noteDao.getNoteById(id);
      expect(stored?.hasLocation, isTrue);
      expect(stored?.latitude, closeTo(30.044420, 0.000001));
      expect(stored?.longitude, closeTo(31.235712, 0.000001));
      expect(stored?.locationAccuracy, closeTo(8.5, 0.000001));
      expect(stored?.locationCapturedAt?.toUtc(), DateTime.utc(2026, 2, 3, 4, 5));
    });

    test('a note without latitude but with longitude has no location', () async {
      final id = await database.noteDao.insertNote(
        Note(
          text: 'broken location',
          longitude: 31.2,
          createdAt: fixedTime,
          updatedAt: fixedTime,
        ),
      );

      final stored = await database.noteDao.getNoteById(id);
      expect(stored?.hasLocation, isFalse);
      expect(stored?.location, isNull);
    });

    test('getNoteById returns null for an unknown id', () async {
      expect(await database.noteDao.getNoteById(9999), isNull);
    });

    test('update changes the row and reports the affected rows', () async {
      final id = await database.noteDao.insertNote(note('before'));
      final stored = (await database.noteDao.getNoteById(id))!;

      final affected = await database.noteDao.updateNote(
        stored.copyWith(text: 'after', updatedAt: fixedTime.add(const Duration(minutes: 1))),
      );

      expect(affected, 1);
      final reloaded = await database.noteDao.getNoteById(id);
      expect(reloaded?.text, 'after');
      expect(reloaded?.updatedAt.toUtc(), fixedTime.add(const Duration(minutes: 1)));
    });

    test('updating an unknown note affects 0 rows instead of crashing', () async {
      final affected = await database.noteDao.updateNote(note('ghost', id: 4242));

      expect(affected, 0);
    });

    test('update can add and remove the location', () async {
      final id = await database.noteDao.insertNote(note('moving'));
      final stored = (await database.noteDao.getNoteById(id))!;

      await database.noteDao.updateNote(
        stored.copyWith(latitude: 10, longitude: 20, locationAccuracy: 3),
      );
      var reloaded = await database.noteDao.getNoteById(id);
      expect(reloaded?.hasLocation, isTrue);

      await database.noteDao.updateNote(reloaded!.copyWith(clearLocation: true));
      reloaded = await database.noteDao.getNoteById(id);
      expect(reloaded?.hasLocation, isFalse);
      expect(reloaded?.locationAccuracy, isNull);
    });

    test('getAllNotes returns the newest update first', () async {
      final old = await database.noteDao.insertNote(note('old'));
      final new1 = await database.noteDao.insertNote(note('new'));

      final stored = (await database.noteDao.getNoteById(new1))!;
      await database.noteDao.updateNote(
        stored.copyWith(updatedAt: fixedTime.add(const Duration(days: 1))),
      );

      final notes = await database.noteDao.getAllNotes();
      expect(notes.map((Note n) => n.id), <int>[new1, old]);
    });

    test('handles a long note without losing characters', () async {
      final longText = List<String>.filled(500, 'abcdefghij').join();
      final id = await database.noteDao.insertNote(note(longText));

      final stored = await database.noteDao.getNoteById(id);
      expect(stored?.text.length, longText.length);
      expect(stored?.text, longText);
    });

    test('deleteNoteById removes the row and is a no-op when missing', () async {
      final id = await database.noteDao.insertNote(note('bye'));

      await database.noteDao.deleteNoteById(id);
      expect(await database.noteDao.getNoteById(id), isNull);
      expect(await database.noteDao.countNotes(), 0);

      // Deleting again must not throw.
      await database.noteDao.deleteNoteById(id);
      await database.noteDao.deleteNoteById(-1);
      expect(await database.noteDao.countNotes(), 0);
    });

    test('deleteAllNotes empties the table and is safe when empty', () async {
      await database.noteDao.insertNote(note('a'));
      await database.noteDao.insertNote(note('b'));
      await database.noteDao.insertNote(note('c'));
      expect(await database.noteDao.countNotes(), 3);

      await database.noteDao.deleteAllNotes();
      expect(await database.noteDao.countNotes(), 0);
      expect(await database.noteDao.getAllNotes(), isEmpty);

      await database.noteDao.deleteAllNotes();
      expect(await database.noteDao.countNotes(), 0);
    });
  });

  group('Note', () {
    test('copyWith keeps the location unless it is cleared', () {
      final original = note(
        'x',
        id: 1,
        location: const NoteLocation(latitude: 1, longitude: 2),
      );

      expect(original.copyWith(text: 'y').latitude, 1);
      expect(original.copyWith(clearLocation: true).location, isNull);
      expect(original.copyWith(clearLocation: true).hasLocation, isFalse);
    });

    test('two notes with the same values are equal', () {
      expect(note('a', id: 3), note('a', id: 3));
      expect(note('a', id: 3).hashCode, note('a', id: 3).hashCode);
      expect(note('a', id: 3), isNot(note('b', id: 3)));
    });

    test('formats the coordinates for the UI', () {
      const location = NoteLocation(latitude: 30, longitude: 31.5, accuracy: 12.4);
      expect(location.coordinates, '30.000000, 31.500000');
      expect(location.displayText, '30.000000, 31.500000  •  ±12 m');
    });

    test('prefers the place name in the one line summary', () {
      const location = NoteLocation(
        latitude: 30,
        longitude: 31.5,
        accuracy: 12.4,
        placeName: 'Dokki, Giza, Egypt',
      );
      expect(location.title, 'Dokki, Giza, Egypt');
      expect(location.displayText, 'Dokki, Giza, Egypt (±12 m)');
      expect(location.coordinatesLabel, '30.000000, 31.500000  •  ±12 m');
    });
  });
}
