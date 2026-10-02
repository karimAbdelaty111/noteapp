# notetask

A Flutter notes app built around **Floor / SQLite**, with optional location
capture and shake-to-delete. No backend, no state-management package: the
database *is* the source of truth, and every screen reloads from it after a
change.

## What it does

- Create, read, edit and delete notes.
- Attach the current location to a note, optionally shown as a readable place
  name (reverse geocoding) with a coordinate fallback.
- Delete from the list by swiping the card left, or with the bin icon.
- Undo a deletion from the snackbar, keeping the original note id.
- Shake the phone to delete every note, behind a confirmation dialog and an
  `UNDO ALL` snackbar.
- Light and dark Material 3 theme, loading skeletons, friendly empty and error
  states, and a retry button.

## Structure

| Path | Purpose |
| --- | --- |
| `lib/database/entities/note.dart` | `Note` and `NoteLocation`; `placeName` is stored in the `place_name` column |
| `lib/database/dao/note_dao.dart` | CRUD plus `countNotesWithId` for safe Undo |
| `lib/database/app_database.dart` | Floor database, schema version 2, v1 → v2 migration |
| `lib/database/converters/` | `DateTime` ↔ epoch-millisecond converters |
| `lib/services/notes_service.dart` | Validation, add/update/delete/restore/delete-all, location preview |
| `lib/services/location_service.dart` | Geolocator + `PlatformGeocoder` (best effort) |
| `lib/services/shake_service.dart` | Accelerometer lifecycle |
| `lib/core/shake_trigger.dart` | Shake threshold, window, count and cooldown |
| `lib/screens/` | List, add, and details screens |
| `lib/widgets/` | Note card, location badge, editor form, empty/error states |
| `lib/theme/app_theme.dart` | Central Material 3 light and dark themes |

## Undo contract

`NotesService.deleteNote` returns the row it deleted, `restoreNote` puts that
exact row back with its original id, and falls back to a new id (with a warning
snackbar) if the id was claimed in the meantime. `deleteAllNotes` and
`restoreNotes` do the same for every note, which is what powers `UNDO ALL`.

## Requirements

- Flutter 3.47.5 / Dart 3.13.4
- Android SDK 36 for Android builds; Xcode for iOS

## Run

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # after entity/DAO changes
flutter run
```

Android already declares `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION`.
iOS declares `NSLocationWhenInUseUsageDescription` in
`ios/Runner/Info.plist`. Both are requested only when the user ticks
*Add current location*, and a refusal never blocks saving a note.

## Test

```bash
flutter analyze
flutter test
```

The suite covers the shake trigger, DAO behaviour, service rules (including
undo, id conflicts, delete-all, geocoding fallback, and file-backed
persistence), and the list, add and details screens.

> Widget tests must give real SQLite time with `tester.runAsync` (see
> `test/support/test_support.dart`); awaiting the database directly inside
> `testWidgets` deadlocks because the test body runs in a fake-async zone.# noteapp
