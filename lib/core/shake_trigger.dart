import 'dart:math' as math;

/// Decides whether an accelerometer reading counts as a *deliberate* shake.
///
/// This class is pure Dart on purpose: it has no Flutter or plugin dependency
/// so the (important) anti false-positive logic can be unit tested.
///
/// The rules are:
///  1. the total acceleration (in g) must exceed [thresholdG] — small
///     movements, such as putting the phone on a table, never pass this test;
///  2. a single spike is not enough, [minimumShakes] spikes are required inside
///     the [shakeWindow];
///  3. two spikes closer than [minimumInterval] to each other count as one
///     (a single shake produces many samples);
///  4. after a shake has fired, the next one is ignored for [cooldown],
///     which stops one shake from triggering several destructive operations.
class ShakeTrigger {
  ShakeTrigger({
    this.thresholdG = 2.7,
    this.minimumShakes = 2,
    this.shakeWindow = const Duration(milliseconds: 1500),
    this.minimumInterval = const Duration(milliseconds: 400),
    this.cooldown = const Duration(milliseconds: 2500),
  });

  /// Acceleration in g that counts as a shake (9.81 m/s² == 1 g).
  final double thresholdG;

  /// How many spikes are needed inside [shakeWindow] to fire.
  final int minimumShakes;

  /// Time window in which the spikes must happen.
  final Duration shakeWindow;

  /// Two spikes closer than this are merged into one.
  final Duration minimumInterval;

  /// Ignore everything after a shake fired for this long.
  final Duration cooldown;

  final List<DateTime> _recentShakes = <DateTime>[];
  DateTime? _lastAcceptedSpike;
  DateTime? _lastFiredAt;

  /// Converts a raw accelerometer sample (m/s²) to g.
  static double toG(double x, double y, double z) {
    final magnitude = math.sqrt(x * x + y * y + z * z);
    return magnitude / _gravity;
  }

  static const double _gravity = 9.80665;

  /// Feeds one accelerometer sample into the detector.
  ///
  /// Returns `true` only when this sample completes a valid shake and the
  /// cooldown has elapsed. Because of the cooldown a single physical shake can
  /// only ever produce one `true`.
  bool addAcceleration(double x, double y, double z, DateTime now) {
    return addGForce(toG(x, y, z), now);
  }

  /// Same as [addAcceleration] but for a reading already expressed in g.
  bool addGForce(double gForce, DateTime now) {
    if (gForce <= thresholdG) return false;

    final lastFiredAt = _lastFiredAt;
    if (lastFiredAt != null && now.difference(lastFiredAt) < cooldown) {
      return false;
    }

    final lastSpike = _lastAcceptedSpike;
    if (lastSpike != null && now.difference(lastSpike) < minimumInterval) {
      // Same physical shake: swallow this extra sample.
      return false;
    }
    _lastAcceptedSpike = now;

    _recentShakes.add(now);
    _recentShakes.removeWhere(
      (DateTime time) => now.difference(time) > shakeWindow,
    );

    if (_recentShakes.length < minimumShakes) return false;

    _recentShakes.clear();
    _lastFiredAt = now;
    return true;
  }

  /// Forgets the current shake gesture (used when detection is restarted).
  void reset() {
    _recentShakes.clear();
    _lastAcceptedSpike = null;
    _lastFiredAt = null;
  }
}
