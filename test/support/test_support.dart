import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notetask/core/shake_trigger.dart';
import 'package:notetask/database/app_database.dart';
import 'package:notetask/database/entities/note.dart';
import 'package:notetask/services/location_service.dart';
import 'package:notetask/services/notes_service.dart';
import 'package:notetask/services/shake_service.dart';

/// Lets the real SQLite I/O finish inside a widget test.
///
/// `pumpAndSettle` alone cannot be used here: the database runs outside the
/// fake-async zone, and the loading spinner animates forever while it is busy,
/// so `pumpAndSettle` would always time out.
Future<void> settle(WidgetTester tester, {int rounds = 25}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Runs a real asynchronous action (database I/O) from inside a `testWidgets`
/// body.
///
/// Awaiting the database directly in a widget test would deadlock, because the
/// test body runs in a fake-async zone where the SQLite isolate reply is never
/// processed. Returns `null` when the action returns `void`.
Future<T?> db<T>(WidgetTester tester, Future<T?> Function() action) async {
  return tester.runAsync<T?>(action);
}

/// Creates a fresh in-memory database for one test.
Future<AppDatabase> createTestDatabase() => openInMemoryNotesDatabase();

/// A [NotesService] with a deterministic clock, so `createdAt`/`updatedAt`
/// can be asserted.
NotesService buildNotesService({
  required AppDatabase database,
  required LocationService locationService,
  DateTime Function()? clock,
}) {
  return NotesService(
    noteDao: database.noteDao,
    locationService: locationService,
    clock: clock ?? () => DateTime.utc(2026, 5, 5, 9),
  );
}

/// A [LocationService] whose answer is decided by the test.
class FakeLocationService implements LocationService {
  FakeLocationService({
    this.result = const LocationResult.failure(
      LocationFailureReason.permissionDenied,
      'Location permission denied.',
    ),
    this.throwsError = false,
  });

  LocationResult result;
  bool throwsError;

  int callCount = 0;

  @override
  Future<LocationResult> getCurrentLocation() async {
    callCount++;
    if (throwsError) {
      throw StateError('the location plugin exploded');
    }
    return result;
  }

  @override
  Future<bool> openLocationSettings() async => false;

  @override
  Future<bool> openAppSettings() async => false;
}

/// A [LocationService] that always returns the same coordinates.
FakeLocationService fixedLocation({
  double latitude = 30.044420,
  double longitude = 31.235712,
  double accuracy = 12,
  String? placeName = 'Dokki, Giza, Egypt',
}) {
  return FakeLocationService(
    result: LocationResult.success(
      NoteLocation(
        latitude: latitude,
        longitude: longitude,
        accuracy: accuracy,
        placeName: placeName,
        capturedAt: DateTime.utc(2026, 5, 5, 10, 30),
      ),
    ),
  );
}

/// A [LocationService] that never succeeds, used to test the "location is
/// optional" rule.
FakeLocationService failingLocation({
  LocationFailureReason reason = LocationFailureReason.permissionDenied,
  String message = 'Location permission denied.',
}) {
  return FakeLocationService(
    result: LocationResult.failure(reason, message),
  );
}

/// Captures the shake callback so a widget test can simulate the gesture
/// without a real accelerometer.
class FakeShakeService implements ShakeService {
  FakeShakeService(this.onShake);

  @override
  final VoidCallback onShake;

  @override
  final ShakeTrigger trigger = ShakeTrigger();

  @override
  final void Function(Object error, StackTrace stackTrace)? onError = null;

  bool started = false;
  bool disposed = false;

  @override
  bool get isRunning => started && !disposed;

  @override
  void start() => started = true;

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  /// Simulates a shake gesture.
  void triggerShake() => onShake();
}
