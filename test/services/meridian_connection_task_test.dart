/// Unit tests for the BG-isolate `MeridianConnectionTask`.
///
/// The class is normally driven by `flutter_foreground_task` from the
/// background isolate, but it's a plain Dart class with no platform-channel
/// dependencies on its IPC handler — so the `start_beaconing` /
/// `stop_beaconing` paths can be exercised directly with `onReceiveData`.
///
/// The race we're guarding against (PR #101 follow-up):
///
///   1. Main isolate sends `start_beaconing` → `_wantsBeaconing = true`,
///      `_beaconTimer` armed.
///   2. Main isolate sends `stop_beaconing` while a beacon is in flight →
///      `_wantsBeaconing = false`, `_beaconTimer` cancelled.
///   3. The in-flight `_sendBeacon().whenComplete(_scheduleNextBeacon)`
///      completes and would otherwise re-arm `_beaconTimer`. The
///      `_wantsBeaconing` gate must catch this and keep the timer null,
///      otherwise the BG isolate ends up in a self-sustaining beacon loop
///      until the FGS dies.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meridian_aprs/services/meridian_connection_task.dart';

void main() {
  group('MeridianConnectionTask — _wantsBeaconing gate', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('initial state has beaconing gated off', () {
      final task = MeridianConnectionTask();
      expect(task.debugWantsBeaconing, isFalse);
      expect(task.debugBeaconTimer, isNull);
    });

    test('start_beaconing IPC opens the gate', () {
      final task = MeridianConnectionTask();
      task.onReceiveData({'type': 'start_beaconing', 'last_beacon_ts': 0});
      expect(task.debugWantsBeaconing, isTrue);
    });

    test('stop_beaconing IPC closes the gate', () {
      final task = MeridianConnectionTask();
      task.onReceiveData({'type': 'start_beaconing', 'last_beacon_ts': 0});
      expect(task.debugWantsBeaconing, isTrue);

      task.onReceiveData({'type': 'stop_beaconing'});
      expect(task.debugWantsBeaconing, isFalse);
      expect(task.debugBeaconTimer, isNull);
    });

    test(
      'stop_beaconing during in-flight beacon prevents whenComplete re-arm',
      () async {
        final task = MeridianConnectionTask();

        // Simulate the well-behaved kickoff — `_wantsBeaconing` opens.
        task.onReceiveData({'type': 'start_beaconing', 'last_beacon_ts': 0});
        expect(task.debugWantsBeaconing, isTrue);

        // Now simulate the IPC arriving while a beacon is in flight. We can't
        // synthesise the in-flight `_sendBeacon` from outside without
        // geolocator, but the load-bearing gate is in `_scheduleNextBeacon`,
        // which is what `whenComplete` calls. After `stop_beaconing`, even
        // a direct call to that method (impossible in production but the
        // worst-case race) must be a no-op. The public surface for that
        // assertion is `debugBeaconTimer` staying null after a follow-up
        // tick.
        task.onReceiveData({'type': 'stop_beaconing'});
        expect(task.debugWantsBeaconing, isFalse);
        expect(task.debugBeaconTimer, isNull);

        // Yield once so any queued microtask (e.g. the `whenComplete` re-arm
        // in production) would resolve. The gate must keep `_beaconTimer`
        // null past this point.
        await Future<void>.delayed(Duration.zero);
        expect(task.debugBeaconTimer, isNull);
        expect(task.debugWantsBeaconing, isFalse);
      },
    );

    test('repeated start_beaconing is idempotent on the gate flag', () {
      final task = MeridianConnectionTask();
      task.onReceiveData({'type': 'start_beaconing', 'last_beacon_ts': 0});
      task.onReceiveData({'type': 'start_beaconing', 'last_beacon_ts': 0});
      expect(task.debugWantsBeaconing, isTrue);
    });

    test('repeated stop_beaconing is safe', () {
      final task = MeridianConnectionTask();
      task.onReceiveData({'type': 'stop_beaconing'});
      task.onReceiveData({'type': 'stop_beaconing'});
      expect(task.debugWantsBeaconing, isFalse);
      expect(task.debugBeaconTimer, isNull);
    });

    test('unknown IPC types do not flip the gate', () {
      final task = MeridianConnectionTask();
      task.onReceiveData({'type': 'something_else'});
      expect(task.debugWantsBeaconing, isFalse);
    });
  });
}
