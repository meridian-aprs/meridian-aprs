import 'dart:async';
import 'dart:math' show min, max;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/station_settings_service.dart';
import '../transport/aprs_is_transport.dart';
import 'meridian_connection.dart';

/// APRS-IS connection over TCP (or WebSocket proxy on web — see ADR-004).
///
/// Wraps [AprsIsTransport] and exposes it through the [MeridianConnection]
/// interface. Beaconing is enabled by default and persisted to
/// SharedPreferences under the key `beacon_enabled_aprs_is`.
///
/// When [StationSettingsService.isLicensed] is false, the APRS-IS login line
/// is substituted with `N0CALL` / passcode `-1` on every [connect] call — see
/// ADR-045.
class AprsIsConnection extends MeridianConnection {
  AprsIsConnection(this._transport, {StationSettingsService? settings})
    : _settings = settings {
    // Mirror every transport state change into a ChangeNotifier notification so
    // that ConnectionRegistry (and all UI widgets watching it) rebuild whenever
    // the socket connects, disconnects, or drops unexpectedly.
    _stateSub = _transport.connectionState.listen((_) => notifyListeners());
  }

  final AprsIsTransport _transport;
  final StationSettingsService? _settings;
  StreamSubscription<ConnectionStatus>? _stateSub;

  static const _kBeaconingKey = 'beacon_enabled_aprs_is';
  static const _kAutoConnectKey = 'aprs_is_auto_connect';

  bool _beaconingEnabled = true;
  bool _autoConnect = false;

  /// Whether the user last chose to have this connection active.
  /// Seeded from SharedPreferences in [loadPersistedSettings]; defaults false
  /// so the connection is opt-in on first launch.
  bool get autoConnect => _autoConnect;

  // ---------------------------------------------------------------------------
  // MeridianConnection — identity
  // ---------------------------------------------------------------------------

  @override
  String get id => 'aprs_is';

  @override
  String get displayName => 'APRS-IS';

  @override
  ConnectionType get type => ConnectionType.aprsIs;

  @override
  bool get isAvailable => !kIsWeb;

  // ---------------------------------------------------------------------------
  // MeridianConnection — state
  // ---------------------------------------------------------------------------

  @override
  ConnectionStatus get status => _transport.currentStatus;

  @override
  Stream<ConnectionStatus> get connectionState => _transport.connectionState;

  @override
  bool get isConnected =>
      _transport.currentStatus == ConnectionStatus.connected;

  // ---------------------------------------------------------------------------
  // MeridianConnection — beaconing
  // ---------------------------------------------------------------------------

  @override
  bool get beaconingEnabled => _beaconingEnabled;

  @override
  Future<void> setBeaconingEnabled(bool enabled) async {
    if (_beaconingEnabled == enabled) return;
    _beaconingEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBeaconingKey, enabled);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // MeridianConnection — data I/O
  // ---------------------------------------------------------------------------

  @override
  Stream<String> get lines => _transport.lines;

  @override
  Future<void> sendLine(String aprsLine) async {
    _transport.sendLine('$aprsLine\r\n');
  }

  // ---------------------------------------------------------------------------
  // MeridianConnection — lifecycle
  // ---------------------------------------------------------------------------

  @override
  Future<void> connect() async {
    _applyLicenseOverride();
    await _transport.connect();
    _autoConnect = true;
    SharedPreferences.getInstance().then(
      (p) => p.setBool(_kAutoConnectKey, true),
    );
    notifyListeners();
  }

  @override
  Future<void> disconnect() async {
    await _transport.disconnect();
    _autoConnect = false;
    SharedPreferences.getInstance().then(
      (p) => p.setBool(_kAutoConnectKey, false),
    );
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    await _stateSub?.cancel();
    await _transport.dispose();
    super.dispose();
  }

  @override
  Future<void> loadPersistedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _beaconingEnabled = prefs.getBool(_kBeaconingKey) ?? true;
    _autoConnect = prefs.getBool(_kAutoConnectKey) ?? false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // APRS-IS specific API
  // ---------------------------------------------------------------------------

  /// Update the login and filter lines used on the next [connect] call.
  ///
  /// Safe to call while disconnected. Has no effect on an active connection —
  /// reconnect to apply the new credentials.
  ///
  /// When [StationSettingsService.isLicensed] is false, the supplied
  /// [loginLine] is overridden with the N0CALL/-1 receive-only form — see
  /// ADR-045.
  void updateCredentials({required String loginLine, String? filterLine}) {
    _transport.updateCredentials(loginLine: loginLine, filterLine: filterLine);
    // Re-apply the override so the stored line reflects the licensed state.
    _applyLicenseOverride(filterLine: filterLine);
  }

  // ---------------------------------------------------------------------------
  // License-mode override
  // ---------------------------------------------------------------------------

  /// When the user is unlicensed, replaces the login line in the underlying
  /// transport with the APRS-IS receive-only form (`N0CALL` / passcode `-1`).
  ///
  /// Called on every [connect] and [updateCredentials] so that a change in
  /// licensed status always takes effect before the next connection attempt.
  /// The [filterLine] is preserved unchanged.
  void _applyLicenseOverride({String? filterLine}) {
    final settings = _settings;
    if (settings == null || settings.isLicensed) return;
    _transport.updateCredentials(
      loginLine: 'user N0CALL pass -1 vers meridian-aprs\r\n',
      filterLine: filterLine,
    );
  }

  /// Send a `#filter b/` bounding-box command derived from the current map
  /// viewport.
  ///
  /// The filter is padded by 25 % on each edge to pre-fetch stations just
  /// outside the visible area, and a minimum of ≈50 km (0.45 °) half-extent is
  /// enforced on each axis so very close zooms still receive a useful feed.
  ///
  /// No-op if the transport is not connected.
  void updateFilter(LatLngBounds bounds) {
    final latPad = (bounds.north - bounds.south) * 0.25;
    final lonPad = (bounds.east - bounds.west) * 0.25;

    final paddedS = bounds.south - latPad;
    final paddedN = bounds.north + latPad;
    final paddedW = bounds.west - lonPad;
    final paddedE = bounds.east + lonPad;

    // Enforce minimum ~50 km equivalent half-extent (≈0.45° lat/lon).
    const minHalf = 0.45;
    final midLat = (paddedS + paddedN) / 2;
    final midLon = (paddedW + paddedE) / 2;
    final effectiveS = min(paddedS, midLat - minHalf).clamp(-90.0, 90.0);
    final effectiveN = max(paddedN, midLat + minHalf).clamp(-90.0, 90.0);
    final effectiveW = min(paddedW, midLon - minHalf);
    final effectiveE = max(paddedE, midLon + minHalf);

    // a/ is the APRS-IS area (bounding-box) filter: a/latN/lonW/latS/lonE.
    // b/ is the budget (callsign) filter — do not use it for geographic filtering.
    final line =
        '#filter a/${effectiveN.toStringAsFixed(2)}/${effectiveW.toStringAsFixed(2)}'
        '/${effectiveS.toStringAsFixed(2)}/${effectiveE.toStringAsFixed(2)}\r\n';
    _transport.sendLine(line);
  }

  /// Build a default bounding-box filter string centred on [lat]/[lon] with a
  /// 1.5 ° half-extent (≈167 km at the equator). Used at connect time when no
  /// viewport bounds are available yet.
  static String defaultFilterLine(double lat, double lon) {
    const half = 1.5;
    final s = (lat - half).clamp(-90.0, 90.0);
    final n = (lat + half).clamp(-90.0, 90.0);
    final w = lon - half;
    final e = lon + half;
    return '#filter a/${n.toStringAsFixed(2)}/${w.toStringAsFixed(2)}'
        '/${s.toStringAsFixed(2)}/${e.toStringAsFixed(2)}\r\n';
  }
}
