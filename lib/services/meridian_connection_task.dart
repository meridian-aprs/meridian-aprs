import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/beaconing/smart_beacon_scheduler.dart';
import '../core/beaconing/smart_beaconing.dart';
import '../core/credentials/credential_key.dart';
import '../core/credentials/secure_credential_store.dart';
import '../core/packet/aprs_encoder.dart';
import '../models/outgoing_bulletin.dart';
import 'beaconing_service.dart' show BeaconMode;
import 'bulletin_service.dart';
import 'messaging_settings_service.dart';

/// Entry point called by flutter_foreground_task when the foreground service
/// starts. Runs in the background isolate.
///
/// Must be a top-level function annotated with @pragma('vm:entry-point') to
/// prevent tree-shaking in release builds.
@pragma('vm:entry-point')
void startMeridianConnectionTask() {
  FlutterForegroundTask.setTaskHandler(MeridianConnectionTask());
}

/// Background-isolate [TaskHandler] that keeps the Android foreground service
/// alive and handles position beaconing while the main isolate is suspended
/// (screen locked).
///
/// **Lifecycle:**
/// - On app backgrounded: [BackgroundServiceManager] calls
///   [FlutterForegroundTask.sendDataToTask] with `{type: start_beaconing}`.
///   The handler schedules a timer and fires beacons at the configured interval.
/// - On app foregrounded: [BackgroundServiceManager] sends `{type: stop_beaconing}`
///   and the timer is cancelled. The main isolate resumes normal beaconing.
///
/// **Settings:** All settings (callsign, symbol, interval, etc.) are read from
/// [SharedPreferences] on each beacon so changes propagate immediately on the
/// next fire.
///
/// **TCP transmission:** Each beacon opens a short-lived TCP connection to
/// `rotate.aprs2.net:14580`, logs in, sends the packet, and closes. This is
/// independent of the main isolate's APRS-IS socket.
class MeridianConnectionTask extends TaskHandler {
  Timer? _beaconTimer;
  Timer? _bulletinTimer;
  int? _lastBeaconTs; // ms since epoch; null until first beacon this session

  /// Master kill-switch for beaconing in this isolate. `true` between
  /// `start_beaconing` and `stop_beaconing` IPCs from the main isolate;
  /// `false` outside that window.
  ///
  /// Load-bearing: `_onBeaconTimer` calls `_sendBeacon().whenComplete(
  /// _scheduleNextBeacon)`. If `stop_beaconing` IPC arrives while
  /// `_sendBeacon` is in flight, `_scheduleNextBeacon` would otherwise
  /// re-arm `_beaconTimer` after the IPC tried to clear it — leaving
  /// the BG isolate firing beacons forever with no way to stop short
  /// of killing the FGS. Every scheduling and transmission entry
  /// point is gated on this flag.
  bool _wantsBeaconing = false;

  /// Active beacon mode for this background session. Set on `start_beaconing`
  /// IPC from the main isolate; treated as auto if not yet set.
  BeaconMode _activeMode = BeaconMode.auto;

  /// Smart-mode scheduler. Non-null only while `_activeMode == BeaconMode.smart`.
  SmartBeaconScheduler? _smart;

  /// GPS position stream subscription. Active only in smart mode.
  StreamSubscription<Position>? _positionSub;

  @visibleForTesting
  bool get debugWantsBeaconing => _wantsBeaconing;

  @visibleForTesting
  Timer? get debugBeaconTimer => _beaconTimer;

  /// Bulletin scheduler tick interval in the background isolate. Matches the
  /// main-isolate `BulletinScheduler` cadence so schedule math is consistent.
  static const _bulletinTickSeconds = 30;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Beacon timer starts only on explicit 'start_beaconing' message from
    // the main isolate. The bulletin timer, in contrast, runs unconditionally
    // while the foreground service is alive — bulletins are independently
    // scheduled per row (ADR-057) and don't need a main-isolate handshake.
    _scheduleNextBulletinTick();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // 60-second heartbeat — prevents aggressive OEM firmware (MIUI, OneUI)
    // from terminating services that show no recent activity.

    // Ask the main isolate to verify each APRS-IS connection is still
    // receiving. Driven from the OS-scheduled FGS heartbeat rather than a
    // Dart Timer because Dart Timers in the main isolate can be stretched
    // arbitrarily under Android Doze, leaving the in-isolate read watchdog
    // unable to fire (Issue #76).
    FlutterForegroundTask.sendDataToMain({
      'type': 'aprs_is_liveness_check',
      'now_ms': DateTime.now().millisecondsSinceEpoch,
    });

    // Also refreshes the "last beacon: Xm ago" notification text so it stays
    // current while the phone is locked (the main isolate cannot do this
    // because its event loop is throttled when backgrounded). The body is
    // only refreshed when this isolate is actually scheduling beacons —
    // otherwise BSM on the main isolate is authoritative for the body
    // (e.g. "Beaconing off" while only a connection is keeping the FGS up).
    if (_beaconTimer == null) return;
    final ts = _lastBeaconTs;
    if (ts == null) return;
    final diffMs = DateTime.now().millisecondsSinceEpoch - ts;
    final minutes = diffMs ~/ 60000;
    final ago = minutes < 1 ? 'just now' : '${minutes}m ago';
    FlutterForegroundTask.updateService(
      notificationText: 'Beaconing · Last beacon: $ago',
    );
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;
    final msg = Map<String, dynamic>.from(data);
    final type = msg['type'] as String?;
    switch (type) {
      case 'start_beaconing':
        _wantsBeaconing = true;
        final lastBeaconTsMs = msg['last_beacon_ts'] as int? ?? 0;
        _scheduleFirstBeacon(lastBeaconTsMs);
      case 'stop_beaconing':
        // Set the gate first so any in-flight `_sendBeacon().whenComplete(
        // _scheduleNextBeacon)` re-arm path no-ops on its next prefs callback.
        _wantsBeaconing = false;
        _beaconTimer?.cancel();
        _beaconTimer = null;
        _stopSmartPositionStream();
        _smart = null;
        _lastBeaconTs =
            null; // Stop onRepeatEvent updating notification after handoff
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    _beaconTimer?.cancel();
    _bulletinTimer?.cancel();
    await _positionSub?.cancel();
    _positionSub = null;
  }

  // ---------------------------------------------------------------------------
  // Beacon scheduling
  // ---------------------------------------------------------------------------

  /// Schedules the first beacon to fire at the right time relative to when the
  /// main isolate last beaconed, so there is no gap after the screen locks.
  void _scheduleFirstBeacon(int lastBeaconTsMs) {
    _beaconTimer?.cancel();
    _stopSmartPositionStream();
    _smart = null;
    // Seed _lastBeaconTs so onRepeatEvent can start updating the notification
    // text immediately, before the first background beacon fires.
    if (lastBeaconTsMs > 0) _lastBeaconTs = lastBeaconTsMs;
    SharedPreferences.getInstance().then((prefs) async {
      await prefs.reload();
      // A `stop_beaconing` IPC could have landed while the prefs load was
      // in flight. Re-check before scheduling anything.
      if (!_wantsBeaconing) return;
      _activeMode = _readBeaconMode(prefs);

      // Manual mode never auto-fires. The user explicitly chose to send only
      // when triggered; the prior background path would auto-fire anyway,
      // which was a separate latent bug — this branch closes it.
      if (_activeMode == BeaconMode.manual) return;

      final intervalS = _resolveInitialIntervalS(prefs);
      final elapsedMs = DateTime.now().millisecondsSinceEpoch - lastBeaconTsMs;
      final elapsedS = elapsedMs ~/ 1000;
      final remainingS = (intervalS - elapsedS).clamp(0, intervalS);
      _beaconTimer = Timer(Duration(seconds: remainingS), _onBeaconTimer);

      if (_activeMode == BeaconMode.smart) {
        final params = _loadSmartParamsFromPrefs(prefs);
        final smart = SmartBeaconScheduler(params: params);
        // Seed the scheduler so the in-flight timer's deadline is visible to
        // onPositionUpdate's only-shorten reschedule check.
        smart.markBeaconSent(
          DateTime.fromMillisecondsSinceEpoch(
            lastBeaconTsMs > 0
                ? lastBeaconTsMs
                : DateTime.now().millisecondsSinceEpoch,
          ),
        );
        smart.seedCurrentTimer(
          startedAt: DateTime.fromMillisecondsSinceEpoch(
            lastBeaconTsMs > 0
                ? lastBeaconTsMs
                : DateTime.now().millisecondsSinceEpoch,
          ),
          intervalS: intervalS,
        );
        _smart = smart;
        await _startSmartPositionStream();
      }
    });
  }

  void _scheduleNextBeacon() {
    // Load-bearing gate against the `whenComplete` race: if `stop_beaconing`
    // landed during `_sendBeacon`, this re-arm path is the one that would
    // otherwise resurrect `_beaconTimer`.
    if (!_wantsBeaconing) return;
    SharedPreferences.getInstance().then((prefs) async {
      await prefs.reload();
      if (!_wantsBeaconing) return;

      if (_activeMode == BeaconMode.manual) return;

      if (_activeMode == BeaconMode.smart && _smart != null) {
        // Hot-reload params so user changes apply on the next cycle without
        // restarting the FGS.
        _smart!.updateParams(_loadSmartParamsFromPrefs(prefs));
        _beaconTimer = Timer(_smart!.intervalAfterBeacon(), _onBeaconTimer);
        return;
      }

      final intervalS = prefs.getInt('beacon_interval_s') ?? 600;
      _beaconTimer = Timer(Duration(seconds: intervalS), _onBeaconTimer);
    });
  }

  void _onBeaconTimer() {
    // whenComplete ensures the next timer is always scheduled, even if _sendBeacon throws.
    _sendBeacon().whenComplete(_scheduleNextBeacon);
  }

  // ---------------------------------------------------------------------------
  // Mode + smart-beaconing helpers
  // ---------------------------------------------------------------------------

  BeaconMode _readBeaconMode(SharedPreferences prefs) {
    final idx = prefs.getInt('beacon_mode') ?? BeaconMode.auto.index;
    if (idx >= 0 && idx < BeaconMode.values.length) {
      return BeaconMode.values[idx];
    }
    return BeaconMode.auto;
  }

  /// Initial interval to use when scheduling the first background beacon.
  /// In smart mode we don't have a speed yet; fall back to slowRate as a
  /// fail-safe upper bound — onPositionUpdate will shorten it once a fix
  /// arrives if the user is moving.
  int _resolveInitialIntervalS(SharedPreferences prefs) {
    if (_activeMode == BeaconMode.smart) {
      return prefs.getInt('smart_slowRateS') ??
          SmartBeaconingParams.defaults.slowRateS;
    }
    return prefs.getInt('beacon_interval_s') ?? 600;
  }

  SmartBeaconingParams _loadSmartParamsFromPrefs(SharedPreferences prefs) {
    final map = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      if (key.startsWith('smart_')) {
        map[key.substring('smart_'.length)] = prefs.get(key);
      }
    }
    return map.isEmpty
        ? SmartBeaconingParams.defaults
        : SmartBeaconingParams.fromMap(map);
  }

  Future<void> _startSmartPositionStream() async {
    await _positionSub?.cancel();
    _positionSub = null;
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await FlutterForegroundTask.updateService(
          notificationText:
              'Smart beaconing unavailable — location service off',
        );
        return;
      }
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        await FlutterForegroundTask.updateService(
          notificationText:
              'Smart beaconing unavailable — location permission required',
        );
        return;
      }
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      ).listen(_onSmartPositionUpdate);
    } catch (_) {
      // Stream couldn't start — fall back to fixed cadence (slowRate timer
      // is already scheduled in _scheduleFirstBeacon / _scheduleNextBeacon).
    }
  }

  void _stopSmartPositionStream() {
    _positionSub?.cancel();
    _positionSub = null;
  }

  void _onSmartPositionUpdate(Position position) {
    if (!_wantsBeaconing) return;
    final smart = _smart;
    if (smart == null || _activeMode != BeaconMode.smart) return;

    final action = smart.onPositionUpdate(position);
    switch (action) {
      case FireNow():
        _beaconTimer?.cancel();
        _beaconTimer = null;
        _onBeaconTimer();
      case Reschedule(:final delay):
        _beaconTimer?.cancel();
        _beaconTimer = Timer(delay, _onBeaconTimer);
      case Keep():
        // No timer change.
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Beacon transmission
  // ---------------------------------------------------------------------------

  Future<void> _sendBeacon() async {
    final prefs = await SharedPreferences.getInstance();
    // reload() re-reads from Android SharedPreferences so we pick up any
    // setting changes made on the main isolate since the background engine
    // started (interval, callsign, beacon targets, etc.). The Dart-side
    // singleton would otherwise serve a stale cached copy indefinitely.
    await prefs.reload();

    // Defense-in-depth: if `stop_beaconing` IPC landed between
    // `_onBeaconTimer` firing and this point, suppress the actual transmit
    // and the side-effects (`_lastBeaconTs`, `bg_last_beacon_ts`,
    // `beacon_sent` IPC, notification body) so the BG isolate doesn't
    // produce phantom log entries after the user disabled beaconing.
    if (!_wantsBeaconing) return;

    final callsign = (prefs.getString('user_callsign') ?? '').toUpperCase();
    if (callsign.isEmpty) return; // Not configured — skip.

    final ssid = prefs.getInt('user_ssid') ?? 0;

    // Passcode lives in the platform secure store rather than SharedPreferences
    // (v0.13 — [SecureCredentialStore]). Reading from here in the background
    // isolate requires flutter_secure_storage to be accessible; on Android and
    // iOS this works because the Keystore/Keychain entries are process-scoped
    // and the plugin initialises itself per isolate. NEEDS-DEVICE-VERIFICATION
    // on first background beacon after upgrade.
    String passcode;
    try {
      passcode =
          await FlutterSecureCredentialStore().read(
            CredentialKey.aprsIsPasscode,
          ) ??
          '-1';
      if (passcode.isEmpty) passcode = '-1';
    } catch (_) {
      passcode = '-1';
    }

    final symbolTable = prefs.getString('user_symbol_table') ?? '/';
    final symbolCode = prefs.getString('user_symbol_code') ?? '>';
    final comment = prefs.getString('user_comment') ?? '';
    final locationSourceIdx = prefs.getInt('user_location_source') ?? 0;

    // Per-connection beaconing flags (ADR-029). Default true so freshly
    // registered connections beacon until the user opts out. The background
    // isolate cannot reach `ConnectionRegistry` (main isolate) so it reads
    // each connection's key directly; the key names are the single source of
    // truth defined on each connection class.
    final beaconToAprsIs = prefs.getBool('beacon_enabled_aprs_is') ?? true;
    final beaconToBleTnc = prefs.getBool('beacon_enabled_ble_tnc') ?? true;
    final beaconToSerialTnc =
        prefs.getBool('beacon_enabled_serial_tnc') ?? true;
    final beaconToAnyTnc = beaconToBleTnc || beaconToSerialTnc;

    if (!beaconToAprsIs && !beaconToAnyTnc) return; // Nothing to do.

    double? lat;
    double? lon;

    if (locationSourceIdx == 0) {
      // GPS source.
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
          ),
        ).timeout(const Duration(seconds: 30));
        lat = pos.latitude;
        lon = pos.longitude;
      } catch (_) {
        return; // GPS unavailable — skip beacon, retry next interval.
      }
    } else {
      // Manual position source.
      lat = prefs.getDouble('user_manual_lat');
      lon = prefs.getDouble('user_manual_lon');
      if (lat == null || lon == null) return;
    }

    final line = AprsEncoder.encodePosition(
      callsign: callsign,
      ssid: ssid,
      lat: lat,
      lon: lon,
      symbolTable: symbolTable,
      symbolCode: symbolCode,
      comment: comment,
    );

    // Transmit to each enabled target independently — one failing does not
    // suppress the other.
    var anySent = false;

    if (beaconToAprsIs) {
      try {
        await _sendToAprsIs(
          callsign: callsign,
          ssid: ssid,
          passcode: passcode,
          line: line,
        );
        anySent = true;
      } catch (_) {
        // APRS-IS failed — continue to TNC path if enabled.
      }
    }

    if (beaconToAnyTnc) {
      // The TNC connection lives on the main isolate. Request transmission via
      // IPC; the main isolate processes this through its event loop while the
      // foreground service wake lock keeps the CPU active.
      FlutterForegroundTask.sendDataToMain({
        'type': 'send_tnc_beacon',
        'aprs_line': line,
      });
      anySent = true;
    }

    if (!anySent) return;

    final tsMs = DateTime.now().millisecondsSinceEpoch;
    _lastBeaconTs = tsMs;

    // Reset the smart scheduler's turn-trigger window so the next sharp turn
    // is measured from this beacon, not from the previous one.
    _smart?.markBeaconSent(DateTime.fromMillisecondsSinceEpoch(tsMs));

    // Persist timestamp to SharedPreferences so the main isolate can sync
    // the BeaconingService timer on resume, even if the IPC message is delayed.
    await prefs.setInt('bg_last_beacon_ts', tsMs);

    // Notify main isolate. This queues if the main isolate is suspended and
    // delivers when it resumes. The aprs_line is included so the main isolate
    // can self-ingest into StationService — same loopback semantics as the
    // foreground BeaconingService.onBeaconSent callback.
    FlutterForegroundTask.sendDataToMain({
      'type': 'beacon_sent',
      'ts': tsMs,
      'aprs_line': line,
    });

    // Update notification body only — title is managed by BackgroundServiceManager
    // on the main isolate and reflects the actual connection state.
    await FlutterForegroundTask.updateService(
      notificationText: 'Beaconing · Last beacon: just now',
    );
  }

  /// Opens a short-lived TCP connection to APRS-IS, logs in, transmits [line],
  /// and closes. Independent of the main isolate's persistent socket.
  Future<void> _sendToAprsIs({
    required String callsign,
    required int ssid,
    required String passcode,
    required String line,
  }) async {
    final addr = ssid == 0 ? callsign : '$callsign-$ssid';
    Socket? socket;
    try {
      socket = await Socket.connect(
        'rotate.aprs2.net',
        14580,
      ).timeout(const Duration(seconds: 15));
      socket.done.ignore();
      socket.write('user $addr pass $passcode vers meridian-aprs 0.7\r\n');
      // Brief pause for the server to acknowledge the login before sending.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      socket.write('$line\r\n');
      await socket.flush();
    } finally {
      socket?.destroy();
    }
  }

  // ---------------------------------------------------------------------------
  // Bulletin scheduling (v0.17, ADR-057)
  // ---------------------------------------------------------------------------
  //
  // Runs while the foreground service is alive so bulletins keep transmitting
  // after the screen locks. The loop reads `OutgoingBulletin` list from
  // SharedPreferences on every tick (same pattern as beacon settings) and
  // writes back state updates — the main isolate's `BulletinService` holds
  // stale in-memory copies during background phase but re-syncs from prefs
  // on UI refresh / app resume.
  //
  // RF transport requests are forwarded to the main isolate via IPC (the
  // TNC connection lives there). APRS-IS transport uses the same short-lived
  // TCP connection helper as the beacon path.

  void _scheduleNextBulletinTick() {
    _bulletinTimer?.cancel();
    _bulletinTimer = Timer(
      const Duration(seconds: _bulletinTickSeconds),
      _onBulletinTick,
    );
  }

  void _onBulletinTick() {
    _processOutgoingBulletins().whenComplete(_scheduleNextBulletinTick);
  }

  Future<void> _processOutgoingBulletins() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final raw = prefs.getString(BulletinService.keyOutgoingBulletins);
    if (raw == null || raw.isEmpty) return;

    final List<OutgoingBulletin> outgoing;
    try {
      outgoing = (jsonDecode(raw) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(OutgoingBulletin.fromJson)
          .toList();
    } catch (_) {
      return;
    }
    if (outgoing.isEmpty) return;

    final callsign = (prefs.getString('user_callsign') ?? '').toUpperCase();
    if (callsign.isEmpty) return;
    final ssid = prefs.getInt('user_ssid') ?? 0;

    final bulletinPath =
        (prefs.getString('messaging_bulletin_path') ??
                MessagingSettingsService.defaultBulletinPath)
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(growable: false);

    String? passcode;
    Future<String> passcodeGetter() async {
      if (passcode != null) return passcode!;
      try {
        final v = await FlutterSecureCredentialStore().read(
          CredentialKey.aprsIsPasscode,
        );
        passcode = (v == null || v.isEmpty) ? '-1' : v;
      } catch (_) {
        passcode = '-1';
      }
      return passcode!;
    }

    var mutated = false;
    final now = DateTime.now();
    for (var i = 0; i < outgoing.length; i++) {
      final ob = outgoing[i];
      if (!ob.enabled) continue;

      // Expiry → disable.
      if (now.isAfter(ob.expiresAt)) {
        outgoing[i] = ob.copyWith(enabled: false);
        mutated = true;
        continue;
      }

      if (ob.isOneShot && ob.transmissionCount > 0) continue;

      final shouldTx =
          ob.lastTransmittedAt == null ||
          now.difference(ob.lastTransmittedAt!) >=
              Duration(seconds: ob.intervalSeconds);
      if (!shouldTx) continue;

      final line = AprsEncoder.encodeBulletin(
        fromCallsign: callsign,
        fromSsid: ssid,
        addressee: ob.addressee,
        body: ob.body,
      );
      var transmitted = false;

      if (ob.viaAprsIs) {
        try {
          await _sendToAprsIs(
            callsign: callsign,
            ssid: ssid,
            passcode: await passcodeGetter(),
            line: line,
          );
          transmitted = true;
        } catch (_) {
          // APRS-IS failed — fall through to RF path.
        }
      }
      if (ob.viaRf) {
        // RF goes through the main isolate's TNC connection. This IPC queues
        // if the main isolate is suspended and delivers when it resumes.
        FlutterForegroundTask.sendDataToMain({
          'type': 'send_tnc_bulletin',
          'aprs_line': line,
          'digipeater_path': bulletinPath,
        });
        transmitted = true;
      }

      if (transmitted) {
        outgoing[i] = ob.copyWith(
          lastTransmittedAt: now,
          transmissionCount: ob.transmissionCount + 1,
        );
        mutated = true;

        // Notify main isolate so the line is self-ingested into StationService —
        // mirrors the beacon_sent loopback so background-fired bulletins appear
        // in the local packet log.
        FlutterForegroundTask.sendDataToMain({
          'type': 'bulletin_sent',
          'aprs_line': line,
        });
      }
    }

    if (mutated) {
      await prefs.setString(
        BulletinService.keyOutgoingBulletins,
        jsonEncode(outgoing.map((ob) => ob.toJson()).toList()),
      );
    }
  }
}
