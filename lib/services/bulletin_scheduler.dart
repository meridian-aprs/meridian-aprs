/// Main-isolate scheduler for outgoing bulletin retransmission.
///
/// Ticks every 30 seconds. For each enabled [OutgoingBulletin]:
///
///   - `now > expiresAt`           → disable, fire `BulletinExpired` event.
///   - one-shot already sent       → skip (stays idle until expiry).
///   - `lastTransmittedAt == null` → **initial pulse** (transmit immediately).
///   - `now - lastTransmittedAt >= intervalSeconds` → transmit.
///
/// See ADR-057. The background-isolate counterpart lives in
/// `meridian_connection_task.dart` and reads the same `OutgoingBulletin` JSON
/// from SharedPreferences on each fire (no IPC state sharing — same pattern
/// as beacon settings).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/packet/aprs_encoder.dart';
import '../models/outgoing_bulletin.dart';
import 'bulletin_service.dart';
import 'messaging_settings_service.dart';
import 'station_settings_service.dart';
import 'tx_service.dart';

/// Event emitted when a scheduler tick transitions an [OutgoingBulletin]
/// from enabled to expired. Consumed by [NotificationService] in PR 5 to
/// fire the "bulletin expired — repost?" notification.
class BulletinExpiredEvent {
  BulletinExpiredEvent(this.bulletin);
  final OutgoingBulletin bulletin;
}

/// Event emitted on every successful transmission. Primarily a test hook
/// today; PR 5 may use it to dedupe notification dispatch against the
/// operator's own bulletins.
class BulletinTransmittedEvent {
  BulletinTransmittedEvent(this.bulletin, this.transmittedAt);
  final OutgoingBulletin bulletin;
  final DateTime transmittedAt;
}

class BulletinScheduler extends ChangeNotifier {
  BulletinScheduler({
    required BulletinService bulletins,
    required TxService tx,
    required MessagingSettingsService messagingSettings,
    required StationSettingsService stationSettings,
    Duration tickInterval = const Duration(seconds: 30),
    DateTime Function()? clock,
  }) : _bulletins = bulletins,
       _tx = tx,
       _messagingSettings = messagingSettings,
       _stationSettings = stationSettings,
       _tickInterval = tickInterval,
       _clock = clock ?? DateTime.now;

  final BulletinService _bulletins;
  final TxService _tx;
  final MessagingSettingsService _messagingSettings;
  final StationSettingsService _stationSettings;
  final Duration _tickInterval;
  final DateTime Function() _clock;

  final _eventController = StreamController<Object>.broadcast();
  Timer? _timer;
  bool _running = false;

  /// True when the scheduler timer is active.
  bool get isRunning => _running;

  /// Stream of [BulletinExpiredEvent] / [BulletinTransmittedEvent] events.
  Stream<Object> get events => _eventController.stream;

  /// Start the periodic tick. Safe to call multiple times — no-op when
  /// already running.
  void start() {
    if (_running) return;
    _running = true;
    _timer = Timer.periodic(_tickInterval, (_) => tick());
    notifyListeners();
  }

  /// Stop the periodic tick. Safe to call when already stopped.
  void stop() {
    if (!_running) return;
    _running = false;
    _timer?.cancel();
    _timer = null;
    notifyListeners();
  }

  /// Run one scheduler pass. Public for tests and for the
  /// background-isolate timer that calls through to the same logic via its
  /// own copy of this method (it can't call this instance — different
  /// isolate). Handles expiry first, then transmission.
  Future<void> tick() async {
    final now = _clock();
    for (final ob in _bulletins.outgoingBulletins.toList()) {
      if (!ob.enabled) continue;

      // 1. Expiry sweep.
      if (now.isAfter(ob.expiresAt)) {
        await _bulletins.setOutgoingEnabled(ob.id, false);
        _eventController.add(BulletinExpiredEvent(ob));
        continue;
      }

      // 2. One-shot already sent — idle until expiry.
      if (ob.isOneShot && ob.transmissionCount > 0) continue;

      // 3. Initial pulse vs. interval retransmission.
      final shouldTransmit =
          ob.lastTransmittedAt == null ||
          now.difference(ob.lastTransmittedAt!) >=
              Duration(seconds: ob.intervalSeconds);
      if (!shouldTransmit) continue;

      await _transmit(ob, now);
    }
  }

  Future<void> _transmit(OutgoingBulletin ob, DateTime now) async {
    final callsign = _stationSettings.callsign.isEmpty
        ? 'NOCALL'
        : _stationSettings.callsign;
    final line = AprsEncoder.encodeBulletin(
      fromCallsign: callsign,
      fromSsid: _stationSettings.ssid,
      addressee: ob.addressee,
      body: ob.body,
    );
    final rfPath = _messagingSettings.bulletinPath
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    try {
      await _tx.sendBulletin(
        line,
        viaRf: ob.viaRf,
        viaAprsIs: ob.viaAprsIs,
        rfPath: rfPath,
      );
      await _bulletins.recordOutgoingTransmission(ob.id, now);
      _eventController.add(BulletinTransmittedEvent(ob, now));
    } catch (e) {
      debugPrint('BulletinScheduler: transmit id=${ob.id} failed: $e');
    }
  }

  @override
  void dispose() {
    stop();
    _eventController.close();
    super.dispose();
  }
}
