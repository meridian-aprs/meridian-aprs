import 'dart:async';
import 'dart:math' show min, max;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import '../transport/aprs_is_transport.dart';
import 'aprs_is_filter_config.dart';
import 'connection_credentials.dart';
import 'lat_lng_box.dart';
import 'meridian_connection.dart';

/// APRS-IS connection over TCP (or WebSocket proxy on web — see ADR-004).
///
/// Wraps [AprsIsTransport] and exposes it through the [MeridianConnection]
/// interface. Beaconing is enabled by default and persisted to
/// SharedPreferences under the key `beacon_enabled_aprs_is`.
///
/// When [ConnectionCredentials.isLicensed] is false, the APRS-IS login line
/// is substituted with `N0CALL` / passcode `-1` on every [connect] call — see
/// ADR-045.
class AprsIsConnection extends MeridianConnection {
  AprsIsConnection(this._transport, {ConnectionCredentials? credentials})
    : _credentials = credentials {
    // Mirror every transport state change into a ChangeNotifier notification so
    // that ConnectionRegistry (and all UI widgets watching it) rebuild whenever
    // the socket connects, disconnects, or drops unexpectedly.
    _stateSub = _transport.connectionState.listen((_) => notifyListeners());
  }

  final AprsIsTransport _transport;
  ConnectionCredentials? _credentials;
  StreamSubscription<ConnectionStatus>? _stateSub;

  static const _kBeaconingKey = 'beacon_enabled_aprs_is';
  static const _kAutoConnectKey = 'aprs_is_auto_connect';

  bool _beaconingEnabled = true;
  bool _autoConnect = false;

  /// Active server-side filter configuration. Defaults to [AprsIsFilterConfig
  /// .defaultConfig] (Regional — the v0.12-equivalent values) so callers that
  /// don't set a config explicitly still get the old behaviour.
  AprsIsFilterConfig _filterConfig = AprsIsFilterConfig.defaultConfig;

  /// Current filter config used by [updateFilter] and [defaultFilterLine].
  AprsIsFilterConfig get filterConfig => _filterConfig;

  /// Replace the active filter configuration. Does not send anything to the
  /// server on its own — the next [updateFilter] call will compose a new
  /// `#filter a/` line using these values.
  void setFilterConfig(AprsIsFilterConfig config) {
    _filterConfig = config;
  }

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
    _applyCredentialsToTransport();
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

  /// Currently-held credentials snapshot, or null if none has been set yet.
  ConnectionCredentials? get credentials => _credentials;

  /// Replace the credentials used on the next [connect] call.
  ///
  /// Safe to call while disconnected. Has no effect on an active connection —
  /// reconnect to apply the new credentials. Also applies the resulting login
  /// line to the underlying transport immediately so that later inspection or
  /// reconnect paths see a consistent value.
  ///
  /// When [ConnectionCredentials.isLicensed] is false, the login line is
  /// overridden with the N0CALL/-1 receive-only form — see ADR-045.
  void setCredentials(ConnectionCredentials credentials, {String? filterLine}) {
    _credentials = credentials;
    _applyCredentialsToTransport(filterLine: filterLine);
  }

  /// Update only the APRS-IS server-side filter line.
  ///
  /// Unlike [setCredentials], this does not touch the login line; safe to call
  /// while connected and the next `#filter` sent via [updateFilter] will
  /// continue to honour it.
  void updateFilterLine(String filterLine) {
    _transport.updateCredentials(
      loginLine: _effectiveLoginLine(),
      filterLine: filterLine,
    );
  }

  // ---------------------------------------------------------------------------
  // License-mode override
  // ---------------------------------------------------------------------------

  /// Computes the login line the transport should carry given the current
  /// credentials and licensed state. Returns the N0CALL/-1 receive-only line
  /// whenever credentials are absent or the user is unlicensed (ADR-045).
  String _effectiveLoginLine() {
    final creds = _credentials;
    if (creds == null || !creds.isLicensed) {
      return 'user N0CALL pass -1 vers meridian-aprs\r\n';
    }
    return creds.aprsIsLoginLine;
  }

  /// Pushes the current effective login (and optional filter) into the
  /// underlying transport. Invoked on [connect] and whenever credentials
  /// change so the licensed-state override always takes effect before the
  /// next connection attempt.
  void _applyCredentialsToTransport({String? filterLine}) {
    _transport.updateCredentials(
      loginLine: _effectiveLoginLine(),
      filterLine: filterLine,
    );
  }

  /// Kilometres per degree of latitude — the flat-earth approximation used
  /// throughout the filter math. Matches the pre-Phase-3 hardcoded value
  /// (0.45° ≈ 50 km) so Regional remains bit-identical to v0.12.
  static const double _kmPerDegree = 111.0;

  /// Send a `#filter a/` bounding-box command derived from the current map
  /// viewport.
  ///
  /// The filter is padded by [AprsIsFilterConfig.padPct] on each edge to
  /// pre-fetch stations just outside the visible area, and a minimum half-
  /// extent of [AprsIsFilterConfig.minRadiusKm] is enforced on each axis so
  /// very close zooms still receive a useful feed. Uses [_filterConfig] by
  /// default; pass [config] explicitly to override for a single call.
  ///
  /// No-op if the transport is not connected.
  void updateFilter(LatLngBox box, {AprsIsFilterConfig? config}) {
    final cfg = config ?? _filterConfig;
    final latPad = (box.north - box.south) * cfg.padPct;
    final lonPad = (box.east - box.west) * cfg.padPct;

    final paddedS = box.south - latPad;
    final paddedN = box.north + latPad;
    final paddedW = box.west - lonPad;
    final paddedE = box.east + lonPad;

    // Enforce minimum radius as a degree half-extent. Uses the same
    // approximation (no cos(lat) correction) as the pre-Phase-3 code so
    // Regional values match v0.12 byte-for-byte.
    final minHalf = cfg.minRadiusKm / _kmPerDegree;
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
  /// generous half-extent. Used at connect time when no viewport bounds are
  /// available yet. The no-viewport case uses at least ~167 km (1.5°) so the
  /// initial feed is useful regardless of the user's preset — a tighter
  /// preset would otherwise starve the first burst of packets.
  static String defaultFilterLine(
    double lat,
    double lon, {
    AprsIsFilterConfig? config,
  }) {
    final cfg = config ?? AprsIsFilterConfig.defaultConfig;
    // Use the preset's minimum radius as a floor but never less than ~167 km
    // so "Local" doesn't collapse the first-connect window to 25 km.
    final km = cfg.minRadiusKm < 167.0 ? 167.0 : cfg.minRadiusKm;
    final half = km / _kmPerDegree;
    final s = (lat - half).clamp(-90.0, 90.0);
    final n = (lat + half).clamp(-90.0, 90.0);
    final w = lon - half;
    final e = lon + half;
    return '#filter a/${n.toStringAsFixed(2)}/${w.toStringAsFixed(2)}'
        '/${s.toStringAsFixed(2)}/${e.toStringAsFixed(2)}\r\n';
  }
}
