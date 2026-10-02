import 'package:flutter_test/flutter_test.dart';
import 'package:notetask/core/shake_trigger.dart';

void main() {
  group('ShakeTrigger.toG', () {
    test('converts m/s^2 into g', () {
      expect(ShakeTrigger.toG(0, 0, 9.80665), closeTo(1, 0.0001));
      expect(ShakeTrigger.toG(9.80665, 9.80665, 9.80665), closeTo(1.7321, 0.001));
    });
  });

  group('ShakeTrigger', () {
    test('ignores small movements', () {
      final trigger = ShakeTrigger();
      var now = DateTime(2026);

      // A phone lying on a table: roughly 1 g.
      for (var i = 0; i < 50; i++) {
        expect(trigger.addGForce(1.0, now), isFalse);
        now = now.add(const Duration(milliseconds: 100));
      }
    });

    test('a single spike below minimumShakeCount does not fire', () {
      final trigger = ShakeTrigger();
      var now = DateTime(2026);

      expect(trigger.addGForce(3.5, now), isFalse, reason: 'first spike');
      now = now.add(const Duration(milliseconds: 50));
      expect(
        trigger.addGForce(3.2, now),
        isFalse,
        reason: 'merged with the first spike (minimum interval)',
      );
    });

    test('two spikes outside the window do not count as one shake', () {
      final trigger = ShakeTrigger(
        shakeWindow: const Duration(milliseconds: 800),
        minimumInterval: const Duration(milliseconds: 400),
      );
      var now = DateTime(2026);

      expect(trigger.addGForce(3.5, now), isFalse);
      now = now.add(const Duration(seconds: 2));
      expect(trigger.addGForce(3.5, now), isFalse, reason: 'too late for the first');
    });

    test('a deliberate shake fires once', () {
      final trigger = ShakeTrigger();
      var now = DateTime(2026);

      expect(trigger.addGForce(3.5, now), isFalse, reason: 'first spike');
      now = now.add(const Duration(milliseconds: 500));
      expect(trigger.addGForce(3.6, now), isTrue, reason: 'second spike');
    });

    test('one shake never fires twice (cooldown)', () {
      final trigger = ShakeTrigger();
      var now = DateTime(2026);

      trigger.addGForce(3.5, now);
      now = now.add(const Duration(milliseconds: 500));
      expect(trigger.addGForce(3.6, now), isTrue);

      // Everything that follows during the cooldown is swallowed.
      for (var i = 1; i <= 10; i++) {
        now = now.add(const Duration(milliseconds: 150));
        expect(trigger.addGForce(4.0, now), isFalse);
      }
    });

    test('spikes further apart than the window are forgotten', () {
      final trigger = ShakeTrigger(shakeWindow: const Duration(milliseconds: 800));
      var now = DateTime(2026);

      trigger.addGForce(3.5, now);
      now = now.add(const Duration(seconds: 2));
      expect(trigger.addGForce(3.5, now), isFalse);
      now = now.add(const Duration(milliseconds: 500));
      expect(trigger.addGForce(3.5, now), isTrue);
    });

    test('samples below the threshold never count', () {
      final trigger = ShakeTrigger(
        minimumShakes: 2,
        minimumInterval: Duration.zero,
      );
      var now = DateTime(2026);

      for (var i = 0; i < 10; i++) {
        expect(trigger.addGForce(2.69, now), isFalse);
        now = now.add(const Duration(milliseconds: 100));
      }
    });

    test('addAcceleration works with raw sensor values', () {
      final trigger = ShakeTrigger();
      var now = DateTime(2026);

      // 3 g on each axis.
      trigger.addAcceleration(3 * 9.80665, 0, 0, now);
      now = now.add(const Duration(milliseconds: 500));
      expect(trigger.addAcceleration(3 * 9.80665, 0, 0, now), isTrue);
    });

    test('reset forgets a partial shake', () {
      final trigger = ShakeTrigger();
      final now = DateTime(2026);

      trigger.addGForce(3.5, now);
      trigger.reset();
      expect(trigger.addGForce(3.5, now.add(const Duration(milliseconds: 500))), isFalse);
    });
  });
}
