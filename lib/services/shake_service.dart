import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../core/shake_trigger.dart';

/// Watches the accelerometer and reports *deliberate* shakes through [onShake].
///
/// All the "how often / how strong" rules live in [ShakeTrigger]; this class
/// only owns the stream subscription and guarantees that [onShake] is called at
/// most once per shake and never after [dispose].
class ShakeService {
  ShakeService({
    required this.onShake,
    ShakeTrigger? trigger,
    this.onError,
  }) : trigger = trigger ?? ShakeTrigger();

  final VoidCallback onShake;

  /// Optional hook so the UI can silently report sensor problems.
  final void Function(Object error, StackTrace stackTrace)? onError;

  final ShakeTrigger trigger;

  StreamSubscription<AccelerometerEvent>? _subscription;
  bool _isRunning = false;

  bool get isRunning => _isRunning;

  /// Starts listening. Calling it twice is a no-op.
  void start() {
    if (_isRunning) return;
    _isRunning = true;
    trigger.reset();
    _subscription = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 100),
    ).listen(
      _handleEvent,
      onError: (Object error, StackTrace stackTrace) {
        onError?.call(error, stackTrace);
      },
      cancelOnError: false,
    );
  }

  void _handleEvent(AccelerometerEvent event) {
    if (!_isRunning) return;
    final now = DateTime.now();
    if (trigger.addAcceleration(event.x, event.y, event.z, now)) {
      onShake();
    }
  }

  /// Stops listening and releases the sensor. Safe to call more than once.
  Future<void> dispose() async {
    _isRunning = false;
    trigger.reset();
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }
}
