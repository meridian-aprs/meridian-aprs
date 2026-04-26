/// Service-level tests for BeaconingService (v0.18 PR 5, issue #52).
///
/// Pins the timer state machine, GPS plumbing, suspend/resume handoff, the
/// onBeaconSent callback fan-out, and the locationUnsupported error path.
/// Pure SmartBeaconing math is covered separately in
/// `test/core/beaconing/smart_beaconing_test.dart`.
///
/// Time control combines `fake_async` (drives Timer + Future scheduling) with
/// the project's injected [Clock] typedef so wall-clock reads and timer fires
/// advance in lock-step.
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meridian_aprs/core/connection/connection_registry.dart';
import 'package:meridian_aprs/services/beaconing_service.dart';
import 'package:meridian_aprs/services/station_settings_service.dart';
import 'package:meridian_aprs/services/tx_service.dart';

import '../helpers/fake_geolocator_adapter.dart';
import '../helpers/fake_secure_credential_store.dart';

// ---------------------------------------------------------------------------
// Recording TxService — captures sendBeacon lines without touching connections.
// ---------------------------------------------------------------------------

class _RecordingTxService extends TxService {
  _RecordingTxService(super.registry, super.settings);
  final List<String> sentBeacons = [];

  @override
  Future<void> sendBeacon(String aprsLine) async {
    sentBeacons.add(aprsLine);
  }
}

// ---------------------------------------------------------------------------
// Fixture
// ---------------------------------------------------------------------------

class _Fixture {
  _Fixture._({
    required this.svc,
    required this.tx,
    required this.geo,
    required this.beaconCallbackLines,
    required this.fakeNow,
  });

  final BeaconingService svc;
  final _RecordingTxService tx;
  final FakeGeolocatorAdapter geo;
  final List<String> beaconCallbackLines;
  final DateTime Function() fakeNow;

  /// Build the fixture inside a `fakeAsync` zone. The returned `Clock` reads
  /// `async.elapsed` so it advances in step with `async.elapse(...)`.
  static Future<_Fixture> build(
    FakeAsync async, {
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues({
      'user_callsign': 'W1ABC',
      'user_ssid': 7,
      'user_is_licensed': true,
      'user_symbol_table': '/',
      'user_symbol_code': '>',
      ...prefs,
    });
    final p = await SharedPreferences.getInstance();
    final settings = StationSettingsService(
      p,
      store: FakeSecureCredentialStore(),
    );
    final registry = ConnectionRegistry();
    final tx = _RecordingTxService(registry, settings);
    final geo = FakeGeolocatorAdapter();

    final start = DateTime(2026, 4, 26, 12, 0, 0);
    DateTime fakeNow() => start.add(async.elapsed);

    final callbackLines = <String>[];
    final svc = BeaconingService(
      settings,
      tx,
      onBeaconSent: callbackLines.add,
      clock: fakeNow,
      geo: geo,
    );

    return _Fixture._(
      svc: svc,
      tx: tx,
      geo: geo,
      beaconCallbackLines: callbackLines,
      fakeNow: fakeNow,
    );
  }
}

/// Build the fixture and run [body] inside a `fakeAsync` zone.
///
/// Wraps the boilerplate so individual tests stay focused on their assertions.
void _runFakeAsync(Future<void> Function(_Fixture f, FakeAsync async) body) {
  fakeAsync((async) {
    late _Fixture f;
    _Fixture.build(async).then((built) => f = built);
    async.flushMicrotasks();
    body(f, async);
    async.flushMicrotasks();
  });
}

/// Position with `speedKmh` (geolocator's [Position.speed] is in m/s).
Position _pos({
  double lat = 30.27,
  double lon = -97.74,
  double speedKmh = 0,
  double heading = 0,
}) => FakeGeolocatorAdapter.position(
  lat: lat,
  lon: lon,
  speed: speedKmh / 3.6,
  heading: heading,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // 1. Mode transitions: timer start/stop on each transition.
  // ---------------------------------------------------------------------------

  group('mode transitions', () {
    test('setMode while inactive does not start a timer', () {
      _runFakeAsync((f, async) async {
        await f.svc.setMode(BeaconMode.auto);
        async.flushMicrotasks();
        async.elapse(const Duration(hours: 2));
        expect(f.tx.sentBeacons, isEmpty);
        expect(f.svc.isActive, isFalse);
      });
    });

    test(
      'startBeaconing in auto schedules at autoIntervalS and fires immediately',
      () {
        _runFakeAsync((f, async) async {
          await f.svc.setMode(BeaconMode.auto);
          await f.svc.setAutoInterval(120);
          unawaited(f.svc.startBeaconing());
          async.flushMicrotasks();
          // Immediate first beacon (standard APRS practice — see
          // beaconing_service.dart:250-252).
          expect(f.tx.sentBeacons, hasLength(1));

          async.elapse(const Duration(seconds: 119));
          expect(f.tx.sentBeacons, hasLength(1));
          async.elapse(const Duration(seconds: 1));
          expect(f.tx.sentBeacons, hasLength(2));
        });
      },
    );

    test('stopBeaconing cancels the timer — no further beacons fire', () {
      _runFakeAsync((f, async) async {
        await f.svc.setMode(BeaconMode.auto);
        await f.svc.setAutoInterval(120);
        unawaited(f.svc.startBeaconing());
        async.flushMicrotasks();
        expect(f.tx.sentBeacons, hasLength(1));

        await f.svc.stopBeaconing();
        async.flushMicrotasks();
        expect(f.svc.isActive, isFalse);

        async.elapse(const Duration(seconds: 600));
        expect(f.tx.sentBeacons, hasLength(1));
      });
    });

    test('setMode while active stops beaconing (current behavior)', () {
      _runFakeAsync((f, async) async {
        await f.svc.setMode(BeaconMode.auto);
        await f.svc.setAutoInterval(120);
        unawaited(f.svc.startBeaconing());
        async.flushMicrotasks();
        expect(f.svc.isActive, isTrue);

        await f.svc.setMode(BeaconMode.smart);
        async.flushMicrotasks();
        expect(
          f.svc.isActive,
          isFalse,
          reason:
              'setMode calls stopBeaconing — see beaconing_service.dart:136',
        );

        // After the mode change there should be no spurious beacons either.
        final countAtSwitch = f.tx.sentBeacons.length;
        async.elapse(const Duration(seconds: 600));
        expect(f.tx.sentBeacons, hasLength(countAtSwitch));
      });
    });

    test('startBeaconing in smart subscribes to the position stream', () {
      _runFakeAsync((f, async) async {
        await f.svc.setMode(BeaconMode.smart);
        unawaited(f.svc.startBeaconing());
        async.flushMicrotasks();
        // Auto mode skips the position stream; smart mode subscribes.
        expect(
          f.geo.getPositionStreamCalls,
          1,
          reason: 'smart mode opens the GPS stream once',
        );
      });
    });
  });

  // ---------------------------------------------------------------------------
  // 2. Smart-mode interval rescheduling.
  // ---------------------------------------------------------------------------

  group('smart interval rescheduling', () {
    test('shortens the interval when speed increases mid-flight', () {
      _runFakeAsync((f, async) async {
        // Start with stationary GPS → slow rate (1800s).
        f.geo.currentPosition = _pos(speedKmh: 0);
        await f.svc.setMode(BeaconMode.smart);
        unawaited(f.svc.startBeaconing());
        async.flushMicrotasks();
        expect(f.tx.sentBeacons, hasLength(1));

        // Stream emits a fast fix. SmartBeaconing.computeInterval(60kmh) ≈ 300s.
        f.geo.emitPosition(_pos(speedKmh: 60));
        async.flushMicrotasks();

        // Advance 300s — the original 1800s timer would not have fired.
        async.elapse(const Duration(seconds: 305));
        expect(
          f.tx.sentBeacons.length,
          greaterThanOrEqualTo(2),
          reason:
              'fast-speed reschedule should shorten the timer well below 1800s',
        );
      });
    });

    test('does NOT extend the interval when speed decreases', () {
      _runFakeAsync((f, async) async {
        // Start with fast GPS → ~300s rate.
        f.geo.currentPosition = _pos(speedKmh: 60);
        await f.svc.setMode(BeaconMode.smart);
        unawaited(f.svc.startBeaconing());
        async.flushMicrotasks();
        expect(f.tx.sentBeacons, hasLength(1));

        // Stream emits a slow fix. New interval = 1800s. Per
        // _rescheduleSmartTimer (beaconing_service.dart:441), only shorten —
        // never push the beacon further out.
        f.geo.emitPosition(_pos(speedKmh: 5));
        async.flushMicrotasks();

        // The original ~300s timer should still fire on schedule.
        async.elapse(const Duration(seconds: 305));
        expect(
          f.tx.sentBeacons.length,
          greaterThanOrEqualTo(2),
          reason: 'slow-speed update must not push the timer out',
        );
      });
    });
  });

  // ---------------------------------------------------------------------------
  // 3. Suspend/resume handoff (the "persistence round-trip" pathway).
  // ---------------------------------------------------------------------------

  group('background handoff', () {
    test(
      'resumeFromBackground restores lastBeaconAt and reschedules the timer',
      () {
        _runFakeAsync((f, async) async {
          await f.svc.setMode(BeaconMode.auto);
          await f.svc.setAutoInterval(600);
          unawaited(f.svc.startBeaconing());
          async.flushMicrotasks();
          expect(f.tx.sentBeacons, hasLength(1));

          // Hand off to the background isolate. Main-isolate timer cancels;
          // isActive remains true.
          f.svc.suspendTimerForBackground();
          expect(f.svc.isActive, isTrue);

          // 200 s of "background" elapse with no main-isolate activity.
          async.elapse(const Duration(seconds: 200));
          expect(f.tx.sentBeacons, hasLength(1));

          // Background isolate beaconed at this moment; foreground returns
          // and replays the last-beacon timestamp.
          final bgBeaconTime = f.fakeNow();
          f.svc.resumeFromBackground(bgBeaconTime);
          expect(f.svc.lastBeaconAt, bgBeaconTime);

          // Timer should be rescheduled to fire 600s after bgBeaconTime.
          async.elapse(const Duration(seconds: 599));
          expect(f.tx.sentBeacons, hasLength(1));
          async.elapse(const Duration(seconds: 1));
          expect(f.tx.sentBeacons, hasLength(2));
        });
      },
    );
  });

  // ---------------------------------------------------------------------------
  // 4. onBeaconSent callback wiring.
  // ---------------------------------------------------------------------------

  group('onBeaconSent', () {
    test('fires exactly once per successful beacon', () {
      _runFakeAsync((f, async) async {
        await f.svc.setMode(BeaconMode.auto);
        await f.svc.setAutoInterval(120);
        unawaited(f.svc.startBeaconing());
        async.flushMicrotasks();
        // Initial beacon.
        expect(f.beaconCallbackLines, hasLength(1));
        expect(f.tx.sentBeacons, hasLength(1));

        // Advance through three timer fires.
        async.elapse(const Duration(seconds: 360));
        expect(f.beaconCallbackLines, hasLength(4));
        expect(f.tx.sentBeacons, hasLength(4));

        // Callback line and TX line agree.
        expect(f.beaconCallbackLines.last, f.tx.sentBeacons.last);
        expect(f.beaconCallbackLines.last, contains('W1ABC-7'));
      });
    });

    test('does NOT fire when manual position is missing', () {
      _runFakeAsync((f, async) async {
        // Switch to manual source without setting coordinates.
        SharedPreferences.setMockInitialValues({
          'user_callsign': 'W1ABC',
          'user_ssid': 7,
          'user_is_licensed': true,
          'user_location_source': LocationSource.manual.index,
        });
        // Rebuild settings/svc with the new prefs. Easiest: reach in via a
        // fresh service since the existing fixture's settings reads prefs at
        // construction.
        final p = await SharedPreferences.getInstance();
        final settings = StationSettingsService(
          p,
          store: FakeSecureCredentialStore(),
        );
        final registry = ConnectionRegistry();
        final tx = _RecordingTxService(registry, settings);
        final geo = FakeGeolocatorAdapter();
        final callbackLines = <String>[];
        final svc = BeaconingService(
          settings,
          tx,
          onBeaconSent: callbackLines.add,
          clock: f.fakeNow,
          geo: geo,
        );

        await svc.beaconNow();
        async.flushMicrotasks();

        expect(callbackLines, isEmpty);
        expect(tx.sentBeacons, isEmpty);
        expect(svc.lastError, BeaconError.noManualPosition);
      });
    });
  });

  // ---------------------------------------------------------------------------
  // 5. BeaconError.locationUnsupported (Linux desktop path).
  // ---------------------------------------------------------------------------

  group('locationUnsupported', () {
    test('a single beaconNow does not loop or crash', () {
      _runFakeAsync((f, async) async {
        f.geo.throwMissingPlugin = true;

        await f.svc.beaconNow();
        async.flushMicrotasks();

        expect(f.svc.lastError, BeaconError.locationUnsupported);
        expect(f.svc.gpsUnsupported, isTrue);
        expect(f.tx.sentBeacons, isEmpty);
        expect(f.beaconCallbackLines, isEmpty);
        expect(
          f.geo.isLocationServiceEnabledCalls,
          1,
          reason:
              'each beaconNow must perform exactly one entry call — no infinite '
              'retry inside a single attempt',
        );
      });
    });

    test('failed beacons do not retrigger the timer chain', () {
      // Each `beaconNow` makes exactly one entry call. When position
      // resolution fails the early-return path skips `_restartTimer`
      // (beaconing_service.dart:194-197), so the one-shot timer chain
      // halts after a single fire. Pinning current behavior — there is
      // no exponential retry, and there is no infinite "tight loop"
      // either.
      _runFakeAsync((f, async) async {
        f.geo.throwMissingPlugin = true;

        await f.svc.setMode(BeaconMode.auto);
        await f.svc.setAutoInterval(120);
        unawaited(f.svc.startBeaconing());
        async.flushMicrotasks();
        // Initial beaconNow inside startBeaconing.
        expect(f.geo.isLocationServiceEnabledCalls, 1);

        // The 120 s one-shot timer scheduled before that first beaconNow
        // still fires once; it then dies because the failed beacon did
        // not reschedule.
        async.elapse(const Duration(seconds: 120));
        expect(f.geo.isLocationServiceEnabledCalls, 2);

        // No further fires for hours — confirms there is no hidden retry
        // loop.
        async.elapse(const Duration(hours: 1));
        expect(f.geo.isLocationServiceEnabledCalls, 2);
        expect(f.tx.sentBeacons, isEmpty);
      });
    });
  });
}

/// Small shim so we can fire-and-forget async functions inside fake_async
/// blocks without analyzer warnings (no `package:async` import needed).
void unawaited(Future<void> _) {}
