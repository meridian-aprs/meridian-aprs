import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:meridian_aprs/core/beaconing/smart_beacon_scheduler.dart';
import 'package:meridian_aprs/core/beaconing/smart_beaconing.dart';

Position _pos({
  required double speedMs,
  required double headingDeg,
  DateTime? timestamp,
}) {
  return Position(
    longitude: 0,
    latitude: 0,
    timestamp: timestamp ?? DateTime.now(),
    accuracy: 1,
    altitude: 0,
    altitudeAccuracy: 1,
    heading: headingDeg,
    headingAccuracy: 1,
    speed: speedMs,
    speedAccuracy: 1,
  );
}

void main() {
  group('SmartBeaconScheduler — intervalAfterBeacon', () {
    test('returns slowRate when no GPS fix yet', () {
      final s = SmartBeaconScheduler(params: SmartBeaconingParams.defaults);
      final d = s.intervalAfterBeacon();
      expect(d.inSeconds, SmartBeaconingParams.defaults.slowRateS);
    });

    test('returns fastRate at or above fastSpeed', () {
      final s = SmartBeaconScheduler(params: SmartBeaconingParams.defaults);
      // 30 m/s = 108 km/h, above fastSpeedKmh=100 default
      s.onPositionUpdate(_pos(speedMs: 30, headingDeg: 0));
      final d = s.intervalAfterBeacon();
      expect(d.inSeconds, SmartBeaconingParams.defaults.fastRateS);
    });

    test('returns slowRate at or below slowSpeed', () {
      final s = SmartBeaconScheduler(params: SmartBeaconingParams.defaults);
      s.onPositionUpdate(_pos(speedMs: 0, headingDeg: 0));
      final d = s.intervalAfterBeacon();
      expect(d.inSeconds, SmartBeaconingParams.defaults.slowRateS);
    });

    test('returns interpolated value at moderate speeds', () {
      final s = SmartBeaconScheduler(params: SmartBeaconingParams.defaults);
      // 14 m/s ~= 50.4 km/h, between slow (5) and fast (100)
      s.onPositionUpdate(_pos(speedMs: 14, headingDeg: 0));
      final d = s.intervalAfterBeacon();
      // SmartBeaconing.computeInterval = (180 * 100 / 50.4).round() = 357
      expect(d.inSeconds, greaterThan(SmartBeaconingParams.defaults.fastRateS));
      expect(d.inSeconds, lessThan(SmartBeaconingParams.defaults.slowRateS));
    });
  });

  group('SmartBeaconScheduler — onPositionUpdate (no prior state)', () {
    test('first position ever returns Keep — no baseline yet', () {
      final s = SmartBeaconScheduler(params: SmartBeaconingParams.defaults);
      final action = s.onPositionUpdate(_pos(speedMs: 20, headingDeg: 0));
      expect(action, isA<Keep>());
    });

    test(
      'second position returns Keep when no timer is active and no beacon yet',
      () {
        final s = SmartBeaconScheduler(params: SmartBeaconingParams.defaults);
        s.onPositionUpdate(_pos(speedMs: 20, headingDeg: 0));
        final action = s.onPositionUpdate(_pos(speedMs: 20, headingDeg: 5));
        // No beacon has fired (markBeaconSent never called) so turn trigger
        // is gated; no timer is set so reschedule is not possible.
        expect(action, isA<Keep>());
      },
    );
  });

  group('SmartBeaconScheduler — turn trigger', () {
    test('sharp turn at speed fires immediately after minTurnTime', () {
      final s = SmartBeaconScheduler(params: SmartBeaconingParams.defaults);
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);

      // Establish baseline: position fix with heading=0, beacon sent.
      s.onPositionUpdate(_pos(speedMs: 20, headingDeg: 0), now: t0);
      s.markBeaconSent(t0);
      s.intervalAfterBeacon(now: t0);

      // 30 s later, heading swings 90° at 20 m/s (~72 km/h).
      // turnThreshold at 72 km/h = (255 / (72/1.609)) + 28 = 5.7 + 28 = 33.7°
      // 90 ≫ 33.7 and 30 s ≥ minTurnTimeS=15 → FireNow.
      final action = s.onPositionUpdate(
        _pos(speedMs: 20, headingDeg: 90),
        now: t0.add(const Duration(seconds: 30)),
      );
      expect(action, isA<FireNow>());
    });

    test('sharp turn before minTurnTime does NOT fire', () {
      final s = SmartBeaconScheduler(params: SmartBeaconingParams.defaults);
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);

      s.onPositionUpdate(_pos(speedMs: 20, headingDeg: 0), now: t0);
      s.markBeaconSent(t0);
      s.intervalAfterBeacon(now: t0);

      // Only 5 s elapsed — minTurnTimeS=15 default, gate blocks.
      final action = s.onPositionUpdate(
        _pos(speedMs: 20, headingDeg: 90),
        now: t0.add(const Duration(seconds: 5)),
      );
      expect(action, isNot(isA<FireNow>()));
    });

    test('small heading delta does not fire even after minTurnTime', () {
      final s = SmartBeaconScheduler(params: SmartBeaconingParams.defaults);
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);

      s.onPositionUpdate(_pos(speedMs: 20, headingDeg: 0), now: t0);
      s.markBeaconSent(t0);
      s.intervalAfterBeacon(now: t0);

      // 5° delta at 72 km/h is well below the ~34° threshold.
      final action = s.onPositionUpdate(
        _pos(speedMs: 20, headingDeg: 5),
        now: t0.add(const Duration(seconds: 60)),
      );
      expect(action, isNot(isA<FireNow>()));
    });

    test('heading wraparound is handled (350° → 10° = 20° delta)', () {
      final s = SmartBeaconScheduler(params: SmartBeaconingParams.defaults);
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);

      s.onPositionUpdate(_pos(speedMs: 20, headingDeg: 350), now: t0);
      s.markBeaconSent(t0);
      s.intervalAfterBeacon(now: t0);

      // Apparent delta = 340°, true delta = 20° → below threshold → no fire.
      final action = s.onPositionUpdate(
        _pos(speedMs: 20, headingDeg: 10),
        now: t0.add(const Duration(seconds: 60)),
      );
      expect(action, isNot(isA<FireNow>()));
    });
  });

  group('SmartBeaconScheduler — reschedule (only shorten)', () {
    test('speed-up shortens timer to new (shorter) interval', () {
      final s = SmartBeaconScheduler(params: SmartBeaconingParams.defaults);
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);

      // Slow start: beacon at slowRate (1800 s).
      s.onPositionUpdate(_pos(speedMs: 0, headingDeg: 0), now: t0);
      s.markBeaconSent(t0);
      s.intervalAfterBeacon(now: t0); // schedules 1800 s timer at t0.

      // 1 s later, accelerate to 30 m/s (108 km/h) → fastRate (180 s).
      // Remaining = 1800 - 1 = 1799 s. New = 180 s. Should reschedule.
      final action = s.onPositionUpdate(
        _pos(speedMs: 30, headingDeg: 0),
        now: t0.add(const Duration(seconds: 1)),
      );
      expect(action, isA<Reschedule>());
      expect(
        (action as Reschedule).delay,
        Duration(seconds: SmartBeaconingParams.defaults.fastRateS),
      );
    });

    test('slowdown does NOT extend timer (keep existing shorter timer)', () {
      final s = SmartBeaconScheduler(params: SmartBeaconingParams.defaults);
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);

      // Fast start: beacon at fastRate (180 s).
      s.onPositionUpdate(_pos(speedMs: 30, headingDeg: 0), now: t0);
      s.markBeaconSent(t0);
      s.intervalAfterBeacon(now: t0); // schedules 180 s timer at t0.

      // 1 s later, slow to a stop → slowRate (1800 s) > remaining (179 s).
      // Should NOT push the beacon out.
      final action = s.onPositionUpdate(
        _pos(speedMs: 0, headingDeg: 0),
        now: t0.add(const Duration(seconds: 1)),
      );
      expect(action, isA<Keep>());
    });

    test('reschedule is suppressed if no timer is active', () {
      final s = SmartBeaconScheduler(params: SmartBeaconingParams.defaults);
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);

      // Two position updates, no markBeaconSent / intervalAfterBeacon.
      s.onPositionUpdate(_pos(speedMs: 0, headingDeg: 0), now: t0);
      final action = s.onPositionUpdate(
        _pos(speedMs: 30, headingDeg: 0),
        now: t0.add(const Duration(seconds: 1)),
      );
      expect(action, isA<Keep>());
    });
  });

  group('SmartBeaconScheduler — updateParams', () {
    test('hot-reload changes subsequent computations', () {
      final s = SmartBeaconScheduler(params: SmartBeaconingParams.defaults);
      s.onPositionUpdate(_pos(speedMs: 0, headingDeg: 0));

      final defaultInterval = s.intervalAfterBeacon();
      expect(
        defaultInterval.inSeconds,
        SmartBeaconingParams.defaults.slowRateS,
      );

      // Tighten slowRate to 600 s and re-check.
      s.updateParams(SmartBeaconingParams.defaults.copyWith(slowRateS: 600));
      final updated = s.intervalAfterBeacon();
      expect(updated.inSeconds, 600);
    });
  });
}
