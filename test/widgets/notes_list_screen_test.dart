import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notetask/database/app_database.dart';
import 'package:notetask/database/entities/note.dart';
import 'package:notetask/screens/notes_list_screen.dart';
import 'package:notetask/services/notes_service.dart';

import '../support/test_support.dart';

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
    try {
      await database.close();
    } on Object {
      // A test may have closed the database on purpose.
    }
  });

  /// Writes notes straight through the service (outside the fake-async zone)
  /// and then pumps the list screen with a fake accelerometer.
  Future<FakeShakeService> pumpList(
    WidgetTester tester, {
    Future<void> Function()? seed,
  }) async {
    if (seed != null) {
      await tester.runAsync<void>(seed);
    }

    late FakeShakeService shakeService;
    await tester.pumpWidget(
      MaterialApp(
        home: NotesListScreen(
          notesService: notesService,
          shakeServiceFactory: (VoidCallback onShake) {
            shakeService = FakeShakeService(onShake);
            return shakeService;
          },
        ),
      ),
    );
    await settle(tester);
    return shakeService;
  }

  /// Drags the card to the left, the way the Dismissible expects it.
  Future<void> swipeLeft(WidgetTester tester, Finder finder) async {
    final gesture = await tester.startGesture(tester.getCenter(finder));
    await tester.pump(const Duration(milliseconds: 60));
    // Well below the 40% threshold: must not delete.
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump(const Duration(milliseconds: 60));
    // Far past the threshold, in a few steps like a real finger.
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(-60, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    // The dismiss animation is finite, so it can be pumped to the end; only
    // then does `onDismissed` fire and the database work start.
    await tester.pumpAndSettle();
  }

  group('empty state', () {
    testWidgets('is friendly and offers the first note', (tester) async {
      await pumpList(tester);

      expect(find.text('No notes yet'), findsOneWidget);
      expect(
        find.text('Create your first note and keep your thoughts organized.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Add note'), findsOneWidget);
      expect(
        find.text('0 notes  •  shake the phone to delete all'),
        findsOneWidget,
      );
    });

    testWidgets('the action opens the add screen', (tester) async {
      await pumpList(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Add note'));
      await settle(tester);

      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.text('New note'), findsOneWidget);
    });
  });

  group('note list', () {
    testWidgets('shows the notes, the place name and the timestamp',
        (tester) async {
      await pumpList(
        tester,
        seed: () async {
          await notesService.addNote(text: 'buy milk');
          await notesService.addNote(text: 'lunch', attachLocation: true);
        },
      );

      expect(find.text('buy milk'), findsOneWidget);
      expect(find.text('lunch'), findsOneWidget);
      expect(find.text('Dokki, Giza, Egypt'), findsOneWidget);
      expect(
        find.text('2 notes  •  shake the phone to delete all'),
        findsOneWidget,
      );
      // A note without a location shows no empty location chip at all.
      expect(find.text('No location'), findsNothing);
    });

    testWidgets('falls back to "Location available" when geocoding failed',
        (tester) async {
      notesService = buildNotesService(
        database: database,
        locationService: fixedLocation(placeName: null),
      );

      await pumpList(
        tester,
        seed: () =>
            notesService.addNote(text: 'somewhere', attachLocation: true),
      );

      expect(find.text('Location available'), findsOneWidget);
    });

    testWidgets('shows a preview of a long note without overflowing',
        (tester) async {
      await pumpList(
        tester,
        seed: () => notesService.addNote(
          text: List<String>.filled(60, 'long note line').join('\n'),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(Card), findsOneWidget);
    });

    testWidgets('the refresh button reloads the list', (tester) async {
      await pumpList(tester);
      expect(find.text('No notes yet'), findsOneWidget);

      // Written straight through the service, so the reload is what is tested.
      await tester.runAsync(() => notesService.addNote(text: 'outside the ui'));
      await tester.tap(find.byTooltip('Refresh'));
      await settle(tester);

      expect(find.text('outside the ui'), findsOneWidget);
      expect(find.text('No notes yet'), findsNothing);
    });

    testWidgets('tapping a note opens its details screen', (tester) async {
      late int noteId;
      await pumpList(
        tester,
        seed: () async {
          noteId = (await notesService.addNote(text: 'open me')).note.id!;
        },
      );

      await tester.tap(find.text('open me'));
      await settle(tester);

      expect(find.text('Edit note'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'open me'), findsOneWidget);
      expect(await tester.runAsync(() => notesService.findNote(noteId)),
          isNotNull);
    });
  });

  group('delete directly from the list', () {
    testWidgets('the bin icon deletes the note and offers UNDO',
        (tester) async {
      await pumpList(
        tester,
        seed: () => notesService.addNote(text: 'delete me'),
      );

      await tester.tap(find.byTooltip('Delete note'));
      await settle(tester);

      expect(await tester.runAsync(() => notesService.countNotes()), 0);
      expect(find.text('No notes yet'), findsOneWidget);
      expect(find.text('Note deleted'), findsOneWidget);
      expect(find.text('UNDO'), findsOneWidget);
    });

    testWidgets('swiping the card deletes the note and offers UNDO',
        (tester) async {
      await pumpList(
        tester,
        seed: () async {
          await notesService.addNote(text: 'swipe me');
          await notesService.addNote(text: 'stay');
        },
      );

      await swipeLeft(tester, find.text('swipe me'));
      await settle(tester);

      expect(await tester.runAsync(() => notesService.countNotes()), 1);
      expect(find.text('swipe me'), findsNothing);
      expect(find.text('stay'), findsOneWidget);
      expect(find.text('UNDO'), findsOneWidget);
    });

    testWidgets('UNDO brings the exact note back through the database',
        (tester) async {
      late NoteIdAndText saved;
      await pumpList(
        tester,
        seed: () async {
          final note = (await notesService.addNote(
            text: 'rescue me',
            attachLocation: true,
          )).note;
          saved = NoteIdAndText(note);
        },
      );

      await tester.tap(find.byTooltip('Delete note'));
      await settle(tester);
      expect(await tester.runAsync(() => notesService.findNote(saved.id!)), isNull);

      await tester.tap(find.text('UNDO'));
      await settle(tester);

      final restored = await tester.runAsync(
        () => notesService.findNote(saved.id!),
      );
      expect(restored, isNotNull, reason: 'the original id is reused');
      expect(restored!.id, saved.id);
      expect(restored.text, 'rescue me');
      expect(restored.createdAt.toUtc(), saved.createdAt.toUtc());
      expect(restored.updatedAt.toUtc(), saved.updatedAt.toUtc());
      expect(restored.hasLocation, isTrue);
      expect(restored.placeName, 'Dokki, Giza, Egypt');
      expect(find.text('rescue me'), findsOneWidget);
    });

    testWidgets('deleting without pressing UNDO leaves the note gone',
        (tester) async {
      await pumpList(
        tester,
        seed: () => notesService.addNote(text: 'gone for good'),
      );

      await tester.tap(find.byTooltip('Delete note'));
      await settle(tester);
      // Let the snackbar expire.
      await settle(tester, rounds: 400);

      expect(await tester.runAsync(() => notesService.countNotes()), 0);
      expect(find.text('No notes yet'), findsOneWidget);
    });

    testWidgets('deleting a second note replaces the first UNDO',
        (tester) async {
      await pumpList(
        tester,
        seed: () async {
          await notesService.addNote(text: 'first');
          await notesService.addNote(text: 'second');
        },
      );

      await tester.tap(find.byTooltip('Delete note').first);
      await settle(tester);
      await tester.tap(find.byTooltip('Delete note').first);
      await settle(tester);

      expect(await tester.runAsync(() => notesService.countNotes()), 0);

      // Only one Undo can be active, so only one note comes back.
      await tester.tap(find.text('UNDO'));
      await settle(tester);

      expect(await tester.runAsync(() => notesService.countNotes()), 1);
    });
  });

  group('shake to delete all', () {
    testWidgets('asks for confirmation and then deletes everything',
        (tester) async {
      final shakeService = await pumpList(
        tester,
        seed: () async {
          await notesService.addNote(text: 'first');
          await notesService.addNote(text: 'second');
        },
      );

      shakeService.triggerShake();
      await settle(tester);

      expect(find.text('Delete all notes?'), findsOneWidget);
      expect(
        find.textContaining('All saved notes will be removed.'),
        findsOneWidget,
      );
      expect(
        await tester.runAsync(() => notesService.countNotes()),
        2,
        reason: 'nothing deleted yet',
      );

      await tester.tap(find.text('DELETE ALL'));
      await settle(tester);

      expect(await tester.runAsync(() => notesService.countNotes()), 0);
      expect(find.text('No notes yet'), findsOneWidget);
      expect(find.text('All notes deleted'), findsOneWidget);
      expect(find.text('UNDO ALL'), findsOneWidget);
    });

    testWidgets('UNDO ALL restores every note through the database',
        (tester) async {
      final shakeService = await pumpList(
        tester,
        seed: () async {
          await notesService.addNote(text: 'first');
          await notesService.addNote(text: 'second', attachLocation: true);
        },
      );

      shakeService.triggerShake();
      await settle(tester);
      await tester.tap(find.text('DELETE ALL'));
      await settle(tester);
      expect(await tester.runAsync(() => notesService.countNotes()), 0);

      await tester.tap(find.text('UNDO ALL'));
      await settle(tester);

      final notes = await tester.runAsync(() => notesService.loadNotes());
      expect(notes, hasLength(2));
      expect(
        notes!.map((note) => note.text),
        containsAll(<String>['first', 'second']),
      );
      expect(
        notes.firstWhere((note) => note.text == 'second').hasLocation,
        isTrue,
      );
      expect(find.text('first'), findsOneWidget);
      expect(find.text('second'), findsOneWidget);
    });

    testWidgets('cancelling keeps every note', (tester) async {
      final shakeService = await pumpList(
        tester,
        seed: () => notesService.addNote(text: 'keep me'),
      );

      shakeService.triggerShake();
      await settle(tester);
      await tester.tap(find.text('CANCEL'));
      await settle(tester);

      expect(await tester.runAsync(() => notesService.countNotes()), 1);
      expect(find.text('keep me'), findsOneWidget);
      expect(find.text('Delete all notes?'), findsNothing);
    });

    testWidgets('a shake on an empty database only shows a message',
        (tester) async {
      final shakeService = await pumpList(tester);

      shakeService.triggerShake();
      await settle(tester);

      expect(find.text('Delete all notes?'), findsNothing);
      expect(find.text('There are no notes to delete.'), findsOneWidget);
    });

    testWidgets('two shakes in a row do not stack two dialogs', (tester) async {
      final shakeService = await pumpList(
        tester,
        seed: () => notesService.addNote(text: 'first'),
      );

      shakeService.triggerShake();
      shakeService.triggerShake();
      await settle(tester);

      expect(find.text('Delete all notes?'), findsOneWidget);
      expect(await tester.runAsync(() => notesService.countNotes()), 1);
    });
  });

  group('robustness', () {
    testWidgets('the accelerometer subscription is released on dispose',
        (tester) async {
      final shakeService = await pumpList(tester);

      expect(shakeService.started, isTrue);
      expect(shakeService.isRunning, isTrue);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('gone'))),
      );

      expect(shakeService.disposed, isTrue);
      expect(shakeService.isRunning, isFalse);
    });

    testWidgets('a database failure shows a friendly error with a retry',
        (tester) async {
      await tester.runAsync(database.close);

      await pumpList(tester);

      expect(find.text("Couldn't load your notes."), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
      // The raw driver error is never shown to the user.
      expect(find.textContaining('DatabaseException'), findsNothing);

      // The retry must not crash even though the database is still closed.
      await tester.tap(find.text('Retry'));
      await settle(tester);
      expect(find.text("Couldn't load your notes."), findsOneWidget);
    });

    testWidgets('leaving the screen while the undo runs is safe', (tester) async {
      await pumpList(
        tester,
        seed: () async {
          await notesService.addNote(text: 'first');
          await notesService.addNote(text: 'second');
        },
      );

      // Delete one note, then press UNDO and immediately leave the screen.
      await tester.tap(find.byTooltip('Delete note').first);
      await settle(tester);
      await tester.tap(find.text('UNDO'));
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('gone'))),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      // The undo still ran against SQLite, exactly once.
      expect(await tester.runAsync(() => notesService.countNotes()), 2);
    });
  });
}

/// Small holder so a seed callback can hand a note back to the test body.
class NoteIdAndText {
  NoteIdAndText(Note note)
    : id = note.id,
      text = note.text,
      createdAt = note.createdAt,
      updatedAt = note.updatedAt;

  final int? id;
  final String text;
  final DateTime createdAt;
  final DateTime updatedAt;
}