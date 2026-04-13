/// Position beaconing service.
///
/// Supports three beacon modes:
/// - [BeaconMode.manual]: send only when explicitly triggered.
/// - [BeaconMode.auto]: fixed-interval timer.
/// - [BeaconMode.smart]: SmartBeaconing™ — adaptive rate based on speed and
///   heading change (see [SmartBeaconing] in lib/core/beaconing/).
///
/// All settings are persisted to [SharedPreferences] immediately on change.
/// GPS access uses the `geolocator` package; permission is requested on the
/// first beacon attempt.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/beaconing/smart_beaconing.dart';
import '../core/packet/aprs_encoder.dart';
import 'station_settings_service.dart';
import 'tx_service.dart';

export '../core/beaconing/smart_beaconing.dart' show SmartBeaconingParams;

/// The three supported beacon modes.
enum BeaconMode { manual, auto, smart }

/// Error reason for the last failed beacon attempt.
enum BeaconError {
  locationPermissionDenied,
  locationServiceDisabled,
  locationUnsupported, // platform has no geolocator implementation (e.g. Linux)
  noManualPosition, // manual source selected but no coordinates stored
  unknown,
}

class BeaconingService extends ChangeNotifier {
  BeaconingService(this._settings, this._tx, {this.onBeaconSent});

  final StationSettingsService _settings;
  final TxService _tx;

  /// Called after every successful beacon with the raw APRS-IS line.
  ///
  /// Wire this to [StationService.ingestLine] so the user's own station
  /// appears on the map immediately without waiting for APRS-IS to echo back
  /// (which it never does for packets originating from the same connection).
  final void Function(String line)? onBeaconSent;

  static const _keyMode = 'beacon_mode';
  static const _keyInterval = 'beacon_interval_s';
  static const _keySmartPrefix = 'smart_';

  BeaconMode _mode = BeaconMode.manual;
  int _autoIntervalS = 600;
  SmartBeaconingParams _smartParams = SmartBeaconingParams.defaults;

  bool _isActive = false;
  DateTime? _lastBeaconAt;
  BeaconError? _lastError;

  // Auto/smart timer
  Timer? _timer;
  DateTime? _timerStartedAt;
  int? _timerIntervalS;

  // GPS / SmartBeaconing state
  Position? _lastPosition;
  double? _lastHeading;
  StreamSubscription<Position>? _positionSub;

  // ---------------------------------------------------------------------------
  // Public read API
  // ---------------------------------------------------------------------------

  BeaconMode get mode => _mode;
  bool get isActive => _isActive;
  int get autoIntervalS => _autoIntervalS;
  SmartBeaconingParams get smartParams => _smartParams;
  DateTime? get lastBeaconAt => _lastBeaconAt;
  BeaconError? get lastError => _lastError;

  /// Human-readable description of when the last beacon was sent.
  String? get lastBeaconAgo {
    if (_lastBeaconAt == null) return null;
    final diff = DateTime.now().difference(_lastBeaconAt!);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  // ---------------------------------------------------------------------------
  // Public mutators
  // ---------------------------------------------------------------------------

  /// Load persisted settings. Call once after construction.
  Future<void> loadPersistedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final modeIdx = prefs.getInt(_keyMode) ?? 0;
    if (modeIdx < BeaconMode.values.length) {
      _mode = BeaconMode.values[modeIdx];
    }
    _autoIntervalS = prefs.getInt(_keyInterval) ?? 600;

    final map = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      if (key.startsWith(_keySmartPrefix)) {
        map[key.substring(_keySmartPrefix.length)] = prefs.get(key);
      }
    }
    if (map.isNotEmpty) {
      _smartParams = SmartBeaconingParams.fromMap(map);
    }
    notifyListeners();
  }

  Future<void> setMode(BeaconMode mode) async {
    if (_mode == mode) return;
    await stopBeaconing();
    _mode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyMode, mode.index);
    notifyListeners();
  }

  Future<void> setAutoInterval(int seconds) async {
    final clamped = seconds.clamp(60, 3600);
    if (_autoIntervalS == clamped) return;
    _autoIntervalS = clamped;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyInterval, clamped);
    if (_isActive && _mode == BeaconMode.auto) {
      await _restartTimer();
    }
    notifyListeners();
  }

  Future<void> setSmartParams(SmartBeaconingParams p) async {
    _smartParams = p;
    final prefs = await SharedPreferences.getInstance();
    for (final entry in p.toMap().entries) {
      final key = '$_keySmartPrefix${entry.key}';
      final v = entry.value;
      if (v is double) await prefs.setDouble(key, v);
      if (v is int) await prefs.setInt(key, v);
    }
    notifyListeners();
  }

  Future<void> resetSmartDefaults() =>
      setSmartParams(SmartBeaconingParams.defaults);

  /// Whether the platform's GPS implementation is known to be unavailable.
  ///
  /// Starts as false (unknown → assume available). Set to true permanently
  /// the first time a [MissingPluginException] is caught — signals the UI
  /// to disable the GPS option.
  bool get gpsUnsupported => _gpsUnsupported;
  bool _gpsUnsupported = false;

  /// Send a beacon immediately. In auto/smart mode, also resets the timer.
  ///
  /// Position is obtained from the source configured in [StationSettingsService]:
  /// - [LocationSource.gps]: requests live GPS. If unavailable the beacon is
  ///   skipped and [lastError] is set — no silent fallback.
  /// - [LocationSource.manual]: uses the stored manual coordinates. If not set
  ///   the beacon is skipped.
  Future<void> beaconNow() async {
    _lastError = null;

    double? lat;
    double? lon;

    if (_settings.locationSource == LocationSource.gps) {
      final position = await _requestPosition();
      if (position == null) {
        // GPS failed — respect the user's choice and skip the beacon.
        notifyListeners();
        return;
      }
      lat = position.latitude;
      lon = position.longitude;
      _lastPosition = position;
    } else {
      // Manual source.
      if (!_settings.hasManualPosition) {
        _lastError = BeaconError.noManualPosition;
        notifyListeners();
        return;
      }
      lat = _settings.manualLat!;
      lon = _settings.manualLon!;
    }

    final aprsLine = AprsEncoder.encodePosition(
      callsign: _settings.callsign.isEmpty ? 'NOCALL' : _settings.callsign,
      ssid: _settings.ssid,
      lat: lat,
      lon: lon,
      symbolTable: _settings.symbolTable,
      symbolCode: _settings.symbolCode,
      comment: _settings.comment,
      hasMessaging: true,
    );

    // Self-ingest before transmitting so the user's own station and packet are
    // always recorded locally, even if the TX attempt fails or the transport
    // does not echo the packet back.
    onBeaconSent?.call(aprsLine);
    await _tx.sendBeacon(aprsLine);
    _lastBeaconAt = DateTime.now();

    if (_isActive) await _restartTimer();
    notifyListeners();
  }

  /// Start auto/smart periodic beaconing.
  Future<void> startBeaconing() async {
    if (_isActive) return;
    _isActive = true;
    // Notify immediately so UI and BackgroundServiceManager update the
    // notification before the first beacon send (which may take several
    // seconds waiting for a GPS fix).
    notifyListeners();
    // Seed _lastBeaconAt so the turn trigger is unblocked from the start.
    // beaconNow() will overwrite this with the real send time on success.
    _lastBeaconAt ??= DateTime.now();
    await _startPositionStream();
    await _restartTimer();
    // Send an immediate first beacon (standard APRS practice). On success this
    // also resets the interval timer relative to the actual send time.
    await beaconNow();
    notifyListeners();
  }

  /// Stop periodic beaconing (does not clear settings or last-beacon time).
  Future<void> stopBeaconing() async {
    if (!_isActive) return;
    _isActive = false;
    _timer?.cancel();
    _timer = null;
    await _positionSub?.cancel();
    _positionSub = null;
    notifyListeners();
  }

  /// Suspends the beacon timer and GPS stream without deactivating beaconing.
  ///
  /// Called by [BackgroundServiceManager] when the Android app is backgrounded
  /// and the background isolate is taking over beacon timing. The main isolate
  /// timer and position subscription are cancelled here so they cannot fire
  /// (and potentially double-transmit) while the background isolate is active.
  /// [isActive] remains true.
  void suspendTimerForBackground() {
    _timer?.cancel();
    _timer = null;
    _positionSub?.cancel();
    _positionSub = null;
    // _isActive intentionally stays true.
  }

  /// Resumes beaconing from a known last-beacon timestamp.
  ///
  /// Called by [BackgroundServiceManager] when the app returns to foreground.
  /// Updates [_lastBeaconAt] to [ts] (the last background beacon time) and
  /// restarts the timer so the next beacon fires [_autoIntervalS] seconds
  /// after [ts].
  void resumeFromBackground(DateTime ts) {
    _timer?.cancel();
    _lastBeaconAt = ts;
    if (_isActive) {
      final elapsed = DateTime.now().difference(ts).inSeconds;
      final remaining = (_autoIntervalS - elapsed).clamp(0, _autoIntervalS);
      _timerStartedAt = ts;
      _timerIntervalS = _autoIntervalS;
      _timer = Timer(Duration(seconds: remaining), _onTimerFired);
      // Restore the GPS position stream for smart mode (was suspended on
      // background handoff to prevent double-transmission with the background
      // isolate's timer).
      if (_mode == BeaconMode.smart) {
        _startPositionStream(); // ignore: unawaited_futures
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positionSub?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Internal — GPS
  // ---------------------------------------------------------------------------

  Future<Position?> _requestPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _lastError = BeaconError.locationServiceDisabled;
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _lastError = BeaconError.locationPermissionDenied;
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );
    } on MissingPluginException {
      // Geolocator has no implementation on this platform (e.g. Linux desktop).
      _gpsUnsupported = true;
      _lastError = BeaconError.locationUnsupported;
      return null;
    } catch (_) {
      _lastError = BeaconError.unknown;
      return null;
    }
  }

  Future<void> _startPositionStream() async {
    await _positionSub?.cancel();
    if (_mode != BeaconMode.smart) return;

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      ).listen(_onPositionUpdate);
    } on MissingPluginException {
      _gpsUnsupported = true;
      _lastError = BeaconError.locationUnsupported;
      notifyListeners();
    }
  }

  void _onPositionUpdate(Position position) {
    if (_mode != BeaconMode.smart || !_isActive) return;

    final speedKmh = (position.speed * 3.6).clamp(0.0, double.infinity);
    final heading = position.heading;

    // Check turn trigger.
    if (_lastPosition != null &&
        _lastBeaconAt != null &&
        _lastHeading != null) {
      final headingDelta = _angleDiff(heading, _lastHeading!);
      final timeSinceLast = DateTime.now().difference(_lastBeaconAt!);
      if (SmartBeaconing.shouldTriggerTurn(
        _smartParams,
        speedKmh,
        headingDelta,
        timeSinceLast,
      )) {
        // Reset heading to current before beaconing so the next delta is
        // measured from the post-turn heading, not the pre-turn heading.
        _lastHeading = heading;
        beaconNow(); // ignore: unawaited_futures
        return;
      }
    }

    _lastHeading = heading;

    // Reschedule interval timer based on new speed.
    if (_timer != null) {
      final newInterval = SmartBeaconing.computeInterval(
        _smartParams,
        speedKmh,
      );
      _rescheduleSmartTimer(newInterval);
    }
  }

  /// Absolute angular difference in [0, 180].
  double _angleDiff(double a, double b) {
    final diff = (a - b).abs() % 360;
    return diff > 180 ? 360 - diff : diff;
  }

  // ---------------------------------------------------------------------------
  // Internal — timer
  // ---------------------------------------------------------------------------

  Future<void> _restartTimer() async {
    _timer?.cancel();
    final intervalS = await _resolveCurrentInterval();
    _timerStartedAt = DateTime.now();
    _timerIntervalS = intervalS;
    _timer = Timer(Duration(seconds: intervalS), _onTimerFired);
  }

  /// Reschedule the smart timer only if [intervalS] would fire sooner than the
  /// current timer. This prevents rapid GPS updates from continually resetting
  /// the timer and delaying beacons indefinitely.
  void _rescheduleSmartTimer(int intervalS) {
    if (_timerStartedAt != null && _timerIntervalS != null) {
      final elapsed = DateTime.now().difference(_timerStartedAt!).inSeconds;
      final remaining = _timerIntervalS! - elapsed;
      // Only shorten — never push the beacon further out.
      if (intervalS >= remaining) return;
    }
    _timer?.cancel();
    _timerStartedAt = DateTime.now();
    _timerIntervalS = intervalS;
    _timer = Timer(Duration(seconds: intervalS), _onTimerFired);
  }

  void _onTimerFired() {
    beaconNow();
  }

  Future<int> _resolveCurrentInterval() async {
    if (_mode == BeaconMode.auto) return _autoIntervalS;
    if (_mode == BeaconMode.smart) {
      final speedKmh = _lastPosition != null
          ? (_lastPosition!.speed * 3.6).clamp(0.0, double.infinity)
          : 0.0;
      return SmartBeaconing.computeInterval(_smartParams, speedKmh);
    }
    return _autoIntervalS;
  }
}
