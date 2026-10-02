import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notetask/database/app_database.dart';
import 'package:notetask/screens/add_note_screen.dart';
import 'package:notetask/screens/note_details_screen.dart';
import 'package:notetask/services/location_service.dart';
import 'package:notetask/services/notes_service.dart';

import '../support/test_support.dart';

void main() {
  late AppDatabase database;
  late NotesService notesService;
  late FakeLocationService locationService;

  setUp(() async {
    database = await createTestDatabase();
    locationService = fixedLocation();
    notesService = buildNotesService(
      database: database,
      locationService: locationService,
    );
  });

  tearDown(() async {
    await database.close();
  });

  /// Opens the add screen the way the list screen does, through a Navigator,
  /// so the SnackBar has a Scaffold to live on after the screen pops.
  Future<void> pumpAddFlow(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => AddNoteScreen(notesService: notesService),
                  ),
                ),
                child: const Text('open add'),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('open add'));
    await settle(tester);
  }

  Future<void> pumpDetails(
    WidgetTester tester,
    int noteId, {
    Future<void> Function()? seed,
  }) async {
    if (seed != null) await tester.runAsync<void>(seed);
    await tester.pumpWidget(
      MaterialApp(
        home: NoteDetailsScreen(notesService: notesService, noteId: noteId),
      ),
    );
    await settle(tester);
  }

  /// Stores a note and returns its id, through the real async zone.
  Future<int> storeNote(
    WidgetTester tester, {
    String text = 'note',
    bool withLocation = false,
  }) async {
    final id = await tester.runAsync<int?>(() async {
      final result = await notesService.addNote(
        text: text,
        attachLocation: withLocation,
      );
      return result.note.id;
    });
    return id!;
  }

  group('Add note', () {
    testWidgets('opens focused with an empty character counter', (tester) async {
      await pumpAddFlow(tester);

      expect(find.text('New note'), findsOneWidget);
      expect(find.text('0 / 4000'), findsOneWidget);
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(
        editable.focusNode.hasFocus,
        isTrue,
        reason: 'the keyboard should open straight away',
      );
    });

    testWidgets('refuses an empty note and explains why', (tester) async {
      await pumpAddFlow(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Save note'));
      await settle(tester);

      // Shown by the field validator and by the SnackBar.
      expect(find.text('A note cannot be empty.'), findsWidgets);
      expect(find.text('New note'), findsOneWidget, reason: 'stays on screen');
      expect(await tester.runAsync(() => notesService.countNotes()), 0);
    });

    testWidgets('refuses a whitespace-only note', (tester) async {
      await pumpAddFlow(tester);

      await tester.enterText(find.byType(TextFormField), '    \n\t ');
      await tester.tap(find.widgetWithText(FilledButton, 'Save note'));
      await settle(tester);

      expect(find.text('A note cannot be empty.'), findsWidgets);
      expect(await tester.runAsync(() => notesService.countNotes()), 0);
    });

    testWidgets('trims the text and reports success', (tester) async {
      await pumpAddFlow(tester);

      await tester.enterText(find.byType(TextFormField), '   buy milk   ');
      await tester.tap(find.widgetWithText(FilledButton, 'Save note'));
      await settle(tester);

      expect(find.text('Note saved'), findsOneWidget);
      final notes = await tester.runAsync(() => notesService.loadNotes());
      expect(notes!.single.text, 'buy milk');
    });

    testWidgets('the character counter follows the input', (tester) async {
      await pumpAddFlow(tester);

      await tester.enterText(find.byType(TextFormField), 'hello');
      await settle(tester);

      expect(find.text('5 / 4000'), findsOneWidget);
    });

    testWidgets('a long note is accepted', (tester) async {
      await pumpAddFlow(tester);

      final longText = 'x' * NotesService.maxLength;
      await tester.enterText(find.byType(TextFormField), longText);
      await tester.tap(find.widgetWithText(FilledButton, 'Save note'));
      await settle(tester);

      final notes = await tester.runAsync(() => notesService.loadNotes());
      expect(notes!.single.text.length, NotesService.maxLength);
    });

    testWidgets('ticking the location box resolves the place name',
        (tester) async {
      await pumpAddFlow(tester);

      await tester.tap(find.text('Add current location'));
      await settle(tester);

      expect(locationService.callCount, 1);
      expect(find.textContaining('Will be attached:'), findsOneWidget);
      expect(find.textContaining('Dokki, Giza, Egypt'), findsWidgets);
    });

    testWidgets('a failing location is explained but the note is saved',
        (tester) async {
      locationService = failingLocation(
        reason: LocationFailureReason.permissionDenied,
        message: 'Location permission denied. The note was saved without a location.',
      );
      notesService = buildNotesService(
        database: database,
        locationService: locationService,
      );

      await pumpAddFlow(tester);
      await tester.enterText(find.byType(TextFormField), 'still saved');
      await tester.tap(find.text('Add current location'));
      await settle(tester);

      expect(
        find.textContaining('Location permission denied'),
        findsWidgets,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Save note'));
      await settle(tester);

      final notes = await tester.runAsync(() => notesService.loadNotes());
      expect(notes!.single.text, 'still saved');
      expect(notes.single.hasLocation, isFalse);
    });

    testWidgets('saving without the location box never calls the plugin',
        (tester) async {
      await pumpAddFlow(tester);

      await tester.enterText(find.byType(TextFormField), 'no location');
      await tester.tap(find.widgetWithText(FilledButton, 'Save note'));
      await settle(tester);

      expect(locationService.callCount, 0);
    });
  });

  group('Note details', () {
    testWidgets('shows the note, the place name and the metadata',
        (tester) async {
      final id = await storeNote(
        tester,
        text: 'lunch break',
        withLocation: true,
      );

      await pumpDetails(tester, id);

      expect(find.text('Edit note'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'lunch break'), findsOneWidget);
      // The readable name is the headline, the numbers are secondary.
      expect(find.text('Dokki, Giza, Egypt'), findsOneWidget);
      expect(find.textContaining('30.044420, 31.235712'), findsOneWidget);
      expect(find.textContaining('id $id'), findsOneWidget);
    });

    testWidgets('hides the location card when there is no location',
        (tester) async {
      final id = await storeNote(tester, text: 'no place');

      await pumpDetails(tester, id);

      expect(find.text('Location'), findsNothing);
      expect(find.text('No location'), findsNothing);
    });

    testWidgets('editing only the text keeps the existing location',
        (tester) async {
      final id = await storeNote(tester, text: 'before', withLocation: true);

      await pumpDetails(tester, id);
      await tester.enterText(find.byType(TextFormField), 'after');
      await tester.tap(find.widgetWithText(FilledButton, 'Update note'));
      await settle(tester);

      expect(find.text('Note updated'), findsOneWidget);
      final stored = await tester.runAsync(() => notesService.findNote(id));
      expect(stored!.text, 'after');
      expect(stored.hasLocation, isTrue, reason: 'location must not be erased');
      expect(stored.placeName, 'Dokki, Giza, Egypt');
      expect(locationService.callCount, 1, reason: 'no extra location request');
    });

    testWidgets('refuses to save an empty note', (tester) async {
      final id = await storeNote(tester, text: 'keep me');

      await pumpDetails(tester, id);
      await tester.enterText(find.byType(TextFormField), '   ');
      await tester.tap(find.widgetWithText(FilledButton, 'Update note'));
      await settle(tester);

      expect(find.text('A note cannot be empty.'), findsWidgets);
      final stored = await tester.runAsync(() => notesService.findNote(id));
      expect(stored!.text, 'keep me');
    });

    testWidgets('can remove the stored location', (tester) async {
      final id = await storeNote(tester, text: 'located', withLocation: true);

      await pumpDetails(tester, id);
      final removeOption = find.text('Remove the stored location');
      await tester.ensureVisible(removeOption);
      await settle(tester);
      await tester.tap(removeOption);
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Update note'));
      await settle(tester);

      final stored = await tester.runAsync(() => notesService.findNote(id));
      expect(stored!.hasLocation, isFalse);
      expect(find.text('Location'), findsNothing);
    });

    testWidgets('delete asks for confirmation first', (tester) async {
      final id = await storeNote(tester, text: 'delete me');

      await pumpDetails(tester, id);
      await tester.tap(find.byTooltip('Delete note'));
      await settle(tester);

      expect(find.text('Delete note?'), findsOneWidget);
      expect(find.text('This action cannot be undone.'), findsOneWidget);
      expect(
        await tester.runAsync(() => notesService.findNote(id)),
        isNotNull,
        reason: 'DELETE has not been pressed',
      );

      await tester.tap(find.text('CANCEL'));
      await settle(tester);

      expect(await tester.runAsync(() => notesService.findNote(id)), isNotNull);
      expect(find.text('Delete note?'), findsNothing);
    });

    testWidgets('confirming the dialog really deletes the note',
        (tester) async {
      final id = await storeNote(tester, text: 'delete me');

      await pumpDetails(tester, id);
      await tester.tap(find.byTooltip('Delete note'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'DELETE'));
      await settle(tester);

      expect(await tester.runAsync(() => notesService.findNote(id)), isNull);
    });

    testWidgets('shows a message when the note disappeared', (tester) async {
      final id = await storeNote(tester, text: 'ghost');
      await tester.runAsync(() => notesService.deleteNote(id));

      await pumpDetails(tester, id);

      expect(find.text('This note was deleted.'), findsOneWidget);
    });
  });
}