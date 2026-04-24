/// Tests for BulletinScheduler (v0.17 PR 4, ADR-057).
///
/// Uses a controllable clock closure to drive ticks without wall-clock
/// waits. The tx path is stubbed via a recording TxService.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meridian_aprs/core/connection/connection_registry.dart';
import 'package:meridian_aprs/services/bulletin_scheduler.dart';
import 'package:meridian_aprs/services/bulletin_service.dart';
import 'package:meridian_aprs/services/bulletin_subscription_service.dart';
import 'package:meridian_aprs/services/messaging_settings_service.dart';
import 'package:meridian_aprs/services/station_settings_service.dart';
import 'package:meridian_aprs/services/tx_service.dart';

import '../helpers/fake_secure_credential_store.dart';

// ---------------------------------------------------------------------------
// Recording TxService — captures sendBulletin calls for assertion.
// ---------------------------------------------------------------------------

class _RecordedSend {
  _RecordedSend(this.line, this.viaRf, this.viaAprsIs, this.rfPath);
  final String line;
  final bool viaRf;
  final bool viaAprsIs;
  final List<String>? rfPath;
}

class _RecordingTxService extends TxService {
  _RecordingTxService(super.registry, super.settings, this.sends);
  final List<_RecordedSend> sends;

  @override
  Future<void> sendBulletin(
    String aprsLine, {
    required bool viaRf,
    required bool viaAprsIs,
    List<String>? rfPath,
  }) async {
    sends.add(_RecordedSend(aprsLine, viaRf, viaAprsIs, rfPath));
  }
}

// ---------------------------------------------------------------------------
// Fixture
// ---------------------------------------------------------------------------

class _Fixture {
  _Fixture._({
    required this.scheduler,
    required this.bulletins,
    required this.sends,
    required this.clock,
  });

  final BulletinScheduler scheduler;
  final BulletinService bulletins;
  final List<_RecordedSend> sends;
  final _MutableClock clock;

  static Future<_Fixture> create({
    DateTime? startAt,
    String bulletinPath = 'WIDE2-2',
  }) async {
    SharedPreferences.setMockInitialValues({
      'user_callsign': 'W1ABC',
      'user_ssid': 7,
      'user_is_licensed': true,
      'messaging_bulletin_path': bulletinPath,
    });
    final prefs = await SharedPreferences.getInstance();
    final settings = StationSettingsService(
      prefs,
      store: FakeSecureCredentialStore(),
    );
    final registry = ConnectionRegistry();
    final subs = BulletinSubscriptionService(prefs: prefs);
    await subs.load();
    final bulletins = BulletinService(subscriptions: subs, prefs: prefs);
    await bulletins.load();
    final messaging = MessagingSettingsService(prefs: prefs);
    await messaging.load();

    final sends = <_RecordedSend>[];
    final tx = _RecordingTxService(registry, settings, sends);
    final clock = _MutableClock(startAt ?? DateTime(2026, 4, 24, 12, 0, 0));

    final scheduler = BulletinScheduler(
      bulletins: bulletins,
      tx: tx,
      messagingSettings: messaging,
      stationSettings: settings,
      tickInterval: const Duration(seconds: 30),
      clock: clock.call,
    );

    return _Fixture._(
      scheduler: scheduler,
      bulletins: bulletins,
      sends: sends,
      clock: clock,
    );
  }
}

class _MutableClock {
  _MutableClock(this._now);
  DateTime _now;

  DateTime call() => _now;

  void advance(Duration d) {
    _now = _now.add(d);
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('initial pulse', () {
    test('fires on the first tick after a bulletin is created', () async {
      final f = await _Fixture.create();
      await f.bulletins.createOutgoing(
        addressee: 'BLN0',
        body: 'Weather alert',
        intervalSeconds: 1800,
      );
      expect(f.sends, isEmpty);

      await f.scheduler.tick();
      expect(f.sends, hasLength(1));
      expect(f.sends.first.line, contains('::BLN0     :Weather alert'));
      expect(f.sends.first.rfPath, ['WIDE2-2']);
    });
  });

  group('interval retransmission', () {
    test('second transmission fires after intervalSeconds', () async {
      final f = await _Fixture.create();
      await f.bulletins.createOutgoing(
        addressee: 'BLN0',
        body: 'test',
        intervalSeconds: 600, // 10 minutes
      );

      // Initial pulse.
      await f.scheduler.tick();
      expect(f.sends, hasLength(1));

      // 5 minutes in — too early.
      f.clock.advance(const Duration(minutes: 5));
      await f.scheduler.tick();
      expect(f.sends, hasLength(1));

      // 10 minutes in — due.
      f.clock.advance(const Duration(minutes: 5));
      await f.scheduler.tick();
      expect(f.sends, hasLength(2));
    });
  });

  group('one-shot', () {
    test('transmits exactly once', () async {
      final f = await _Fixture.create();
      await f.bulletins.createOutgoing(
        addressee: 'BLN0',
        body: 'test',
        intervalSeconds: 0, // one-shot
      );

      await f.scheduler.tick();
      expect(f.sends, hasLength(1));

      // Many more ticks with time advancing — should stay at 1.
      for (var i = 0; i < 10; i++) {
        f.clock.advance(const Duration(hours: 1));
        await f.scheduler.tick();
      }
      expect(f.sends, hasLength(1));
    });
  });

  group('expiry', () {
    test(
      'expired bulletin is disabled and fires BulletinExpiredEvent',
      () async {
        final f = await _Fixture.create();
        final expiresAt = f.clock().add(const Duration(hours: 1));
        final ob = await f.bulletins.createOutgoing(
          addressee: 'BLN0',
          body: 'test',
          intervalSeconds: 1800,
          expiresAt: expiresAt,
        );

        final events = <Object>[];
        f.scheduler.events.listen(events.add);

        // Initial pulse.
        await f.scheduler.tick();
        expect(f.sends, hasLength(1));

        // Advance past expiry.
        f.clock.advance(const Duration(hours: 2));
        await f.scheduler.tick();

        // No new transmission, expired event fired, row disabled.
        expect(f.sends, hasLength(1));
        await Future<void>.delayed(Duration.zero);
        expect(events.whereType<BulletinExpiredEvent>(), hasLength(1));
        expect(f.bulletins.outgoingById(ob.id)!.enabled, isFalse);
      },
    );
  });

  group('edit semantics', () {
    test('editing body resets state — initial pulse on next tick', () async {
      final f = await _Fixture.create();
      final ob = await f.bulletins.createOutgoing(
        addressee: 'BLN0',
        body: 'old',
        intervalSeconds: 1800,
      );
      await f.scheduler.tick();
      expect(f.sends, hasLength(1));

      // 5 min in — below interval, no TX.
      f.clock.advance(const Duration(minutes: 5));
      await f.scheduler.tick();
      expect(f.sends, hasLength(1));

      // Edit body. Per ADR-057 this resets state.
      await f.bulletins.updateOutgoingContent(ob.id, body: 'new');
      expect(f.bulletins.outgoingById(ob.id)!.lastTransmittedAt, isNull);
      expect(f.bulletins.outgoingById(ob.id)!.transmissionCount, 0);

      // Next tick — initial pulse of new body, even though only 5 min elapsed.
      await f.scheduler.tick();
      expect(f.sends, hasLength(2));
      expect(f.sends.last.line, contains(':new'));
    });

    test('editing interval only does NOT reset state', () async {
      final f = await _Fixture.create();
      final ob = await f.bulletins.createOutgoing(
        addressee: 'BLN0',
        body: 'body',
        intervalSeconds: 1800,
      );
      await f.scheduler.tick(); // initial pulse
      expect(f.sends, hasLength(1));
      final originalLastTx = f.bulletins.outgoingById(ob.id)!.lastTransmittedAt;
      expect(originalLastTx, isNotNull);

      // Change interval — state preserved.
      await f.bulletins.updateOutgoingSchedule(ob.id, intervalSeconds: 600);
      final after = f.bulletins.outgoingById(ob.id)!;
      expect(after.lastTransmittedAt, originalLastTx);
      expect(after.transmissionCount, 1);
      expect(after.intervalSeconds, 600);

      // 5 min advance → now interval has passed under the new schedule.
      f.clock.advance(const Duration(minutes: 11));
      await f.scheduler.tick();
      expect(f.sends, hasLength(2));
    });
  });

  group('enable/disable + delete', () {
    test('disabled bulletin does not transmit', () async {
      final f = await _Fixture.create();
      final ob = await f.bulletins.createOutgoing(
        addressee: 'BLN0',
        body: 'test',
        intervalSeconds: 1800,
      );
      await f.bulletins.setOutgoingEnabled(ob.id, false);

      await f.scheduler.tick();
      f.clock.advance(const Duration(hours: 1));
      await f.scheduler.tick();
      expect(f.sends, isEmpty);
    });

    test('deleted bulletin stops transmitting', () async {
      final f = await _Fixture.create();
      final ob = await f.bulletins.createOutgoing(
        addressee: 'BLN0',
        body: 'test',
        intervalSeconds: 600,
      );
      await f.scheduler.tick();
      expect(f.sends, hasLength(1));

      await f.bulletins.deleteOutgoing(ob.id);
      f.clock.advance(const Duration(hours: 1));
      await f.scheduler.tick();
      expect(f.sends, hasLength(1));
    });
  });

  group('transport flags', () {
    test('viaRf=false + viaAprsIs=true sends only via IS', () async {
      final f = await _Fixture.create();
      await f.bulletins.createOutgoing(
        addressee: 'BLN0',
        body: 'test',
        intervalSeconds: 0,
        viaRf: false,
        viaAprsIs: true,
      );
      await f.scheduler.tick();
      expect(f.sends, hasLength(1));
      expect(f.sends.first.viaRf, isFalse);
      expect(f.sends.first.viaAprsIs, isTrue);
    });

    test('rfPath honors Advanced-mode setting', () async {
      final f = await _Fixture.create(bulletinPath: 'WIDE1-1,WIDE2-2');
      await f.bulletins.createOutgoing(
        addressee: 'BLN0',
        body: 'test',
        intervalSeconds: 0,
      );
      await f.scheduler.tick();
      expect(f.sends.first.rfPath, ['WIDE1-1', 'WIDE2-2']);
    });
  });

  group('start/stop lifecycle', () {
    test('start() registers a periodic timer, stop() cancels it', () async {
      final f = await _Fixture.create();
      expect(f.scheduler.isRunning, isFalse);
      f.scheduler.start();
      expect(f.scheduler.isRunning, isTrue);
      f.scheduler.stop();
      expect(f.scheduler.isRunning, isFalse);
    });
  });
}
