import 'package:flutter_test/flutter_test.dart';

import 'package:meridian_aprs/core/beaconing/smart_beaconing.dart';

void main() {
  const p = SmartBeaconingParams.defaults;
  // defaults: fastSpeed=100, fastRate=180, slowSpeed=5, slowRate=1800,
  //           minTurnTime=15, minTurnAngle=28, turnSlope=255

  group('SmartBeaconing.computeInterval', () {
    test('at or above fast speed → fast rate', () {
      expect(SmartBeaconing.computeInterval(p, 100), equals(180));
      expect(SmartBeaconing.computeInterval(p, 150), equals(180));
    });

    test('at or below slow speed → slow rate', () {
      expect(SmartBeaconing.computeInterval(p, 5), equals(1800));
      expect(SmartBeaconing.computeInterval(p, 0), equals(1800));
    });

    test('at midpoint speed → inverse-proportional interval', () {
      // inverse formula: fast_rate × fast_speed / speed
      // 180 × 100 / 52.5 ≈ 343 s
      final interval = SmartBeaconing.computeInterval(p, 52.5);
      expect(interval, closeTo(343, 2));
    });

    test('interval is between fastRate and slowRate for in-range speeds', () {
      for (final speed in [10.0, 30.0, 70.0, 90.0]) {
        final interval = SmartBeaconing.computeInterval(p, speed);
        expect(interval, greaterThanOrEqualTo(p.fastRateS));
        expect(interval, lessThanOrEqualTo(p.slowRateS));
      }
    });
  });

  group('SmartBeaconing.turnThreshold', () {
    test('returns 180 for zero speed', () {
      expect(SmartBeaconing.turnThreshold(p, 0), equals(180.0));
    });

    test('decreases as speed increases', () {
      final t10 = SmartBeaconing.turnThreshold(p, 10);
      final t50 = SmartBeaconing.turnThreshold(p, 50);
      final t100 = SmartBeaconing.turnThreshold(p, 100);
      expect(t10, greaterThan(t50));
      expect(t50, greaterThan(t100));
    });

    test('at 50 km/h → 255/31.07mph + 28 ≈ 36.2°', () {
      // turnSlope has units of degrees·mph; 50 km/h = 31.07 mph
      // 255 / 31.07 + 28 ≈ 36.2°
      final t = SmartBeaconing.turnThreshold(p, 50);
      expect(t, closeTo(36.2, 0.1));
    });

    test('never exceeds 180', () {
      expect(SmartBeaconing.turnThreshold(p, 0.001), lessThanOrEqualTo(180));
    });
  });

  group('SmartBeaconing.shouldTriggerTurn', () {
    const fastEnough = Duration(seconds: 30); // > minTurnTime(15)
    const tooSoon = Duration(seconds: 10); // < minTurnTime(15)

    test('returns false when within minTurnTime cooldown', () {
      // At 50 km/h threshold ≈ 36.2°; heading change 90° but too soon
      expect(SmartBeaconing.shouldTriggerTurn(p, 50, 90, tooSoon), isFalse);
    });

    test('returns false when heading change is below threshold', () {
      // At 50 km/h threshold ≈ 36.2°; heading change only 20°
      expect(SmartBeaconing.shouldTriggerTurn(p, 50, 20, fastEnough), isFalse);
    });

    test('returns true when above threshold and cooldown elapsed', () {
      // At 50 km/h threshold ≈ 36.2°; heading change 45°
      expect(SmartBeaconing.shouldTriggerTurn(p, 50, 45, fastEnough), isTrue);
    });

    test('handles negative heading changes (treated as absolute value)', () {
      // Turning -90° at 50 km/h should trigger
      expect(SmartBeaconing.shouldTriggerTurn(p, 50, -90, fastEnough), isTrue);
    });

    test('exactly at threshold angle triggers', () {
      // At 50 km/h threshold ≈ 36.2°
      final threshold = SmartBeaconing.turnThreshold(p, 50);
      expect(
        SmartBeaconing.shouldTriggerTurn(p, 50, threshold, fastEnough),
        isTrue,
      );
    });

    test('just below threshold angle does not trigger', () {
      final threshold = SmartBeaconing.turnThreshold(p, 50);
      expect(
        SmartBeaconing.shouldTriggerTurn(p, 50, threshold - 0.1, fastEnough),
        isFalse,
      );
    });

    test('at speed 0 → threshold is 180°, only extreme turns trigger', () {
      // Heading change of 180° at speed 0 should trigger (just at limit)
      expect(SmartBeaconing.shouldTriggerTurn(p, 0, 180, fastEnough), isTrue);
      // 179° should not
      expect(SmartBeaconing.shouldTriggerTurn(p, 0, 179, fastEnough), isFalse);
    });
  });

  group('SmartBeaconingParams serialization', () {
    test('round-trips through toMap/fromMap', () {
      const original = SmartBeaconingParams.defaults;
      final map = original.toMap();
      final restored = SmartBeaconingParams.fromMap(map);
      expect(restored.fastSpeedKmh, equals(original.fastSpeedKmh));
      expect(restored.fastRateS, equals(original.fastRateS));
      expect(restored.slowSpeedKmh, equals(original.slowSpeedKmh));
      expect(restored.slowRateS, equals(original.slowRateS));
      expect(restored.minTurnTimeS, equals(original.minTurnTimeS));
      expect(restored.minTurnAngleDeg, equals(original.minTurnAngleDeg));
      expect(restored.turnSlope, equals(original.turnSlope));
    });

    test('fromMap with missing keys falls back to defaults', () {
      final restored = SmartBeaconingParams.fromMap({});
      expect(
        restored.fastSpeedKmh,
        equals(SmartBeaconingParams.defaults.fastSpeedKmh),
      );
    });
  });
}
