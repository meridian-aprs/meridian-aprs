import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import '../transport/aprs_is_transport.dart';
import 'aprs_is_filter_builder.dart';
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
  static const _kServerOverrideKey = 'aprs_is_server_override';

  static const _defaultHost = 'rotate.aprs2.net';
  static const _defaultPort = 14580;

  bool _beaconingEnabled = true;
  bool _autoConnect = false;

  /// Active server-side filter configuration. Defaults to [AprsIsFilterConfig
  /// .defaultConfig] (Regional — the v0.12-equivalent values) so callers that
  /// don't set a config explicitly still get the old behaviour.
  AprsIsFilterConfig _filterConfig = AprsIsFilterConfig.defaultConfig;

  /// Most recent viewport box sent through [updateFilter]. Null until the
  /// first viewport update fires. Used by [onSubscriptionsChanged] so a
  /// subscription change can rebuild and re-send the filter without waiting
  /// for the next map move.
  LatLngBox? _lastBox;

  /// Latest named-bulletin-group names to include in the filter. Pushed in
  /// by [ConnectionRegistry.loadAllSettings] + a listener on
  /// [BulletinSubscriptionService] (v0.17 PR 5, ADR-058).
  List<String> _namedBulletinGroups = const [];

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
  Future<void> sendLine(String aprsLine, {List<String>? digipeaterPath}) async {
    // digipeaterPath is ignored — APRS-IS has no concept of a digipeater path.
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

  /// Recycle the socket without flipping the user-facing auto-connect intent.
  /// Used by background watchdogs (Issue #76) that have detected the socket
  /// is wedged but the user has not asked to disconnect.
  @override
  Future<void> recycle() async {
    _applyCredentialsToTransport();
    await _transport.forceReset();
    await _transport.connect();
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    await _stateSub?.cancel();
    await _transport.dispose();
    super.dispose();
  }

  /// Wall-clock timestamp of the most recently received line on the underlying
  /// transport, or null if nothing has arrived yet. Exposed so the foreground
  /// service heartbeat can detect staleness without inspecting the transport
  /// directly.
  DateTime? get lastLineAt => _transport.lastLineAt;

  @override
  Future<void> loadPersistedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _beaconingEnabled = prefs.getBool(_kBeaconingKey) ?? true;
    _autoConnect = prefs.getBool(_kAutoConnectKey) ?? false;
    final override = prefs.getString(_kServerOverrideKey);
    if (override != null && override.isNotEmpty) {
      _applyServerOverride(override);
    }
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

  /// The currently active server displayed as "host:port".
  String get serverDisplay => '${_transport.host}:${_transport.port}';

  /// Whether a non-default server override is active.
  bool get hasServerOverride =>
      _transport.host != _defaultHost || _transport.port != _defaultPort;

  /// Persist and apply a server override ("host:port"), or clear it when null.
  ///
  /// Takes effect on the next [connect] call. Does not automatically reconnect.
  Future<void> setServerOverride(String? override) async {
    final prefs = await SharedPreferences.getInstance();
    if (override == null || override.isEmpty) {
      await prefs.remove(_kServerOverrideKey);
      _transport.updateServer(host: _defaultHost, port: _defaultPort);
    } else {
      _applyServerOverride(override);
      await prefs.setString(_kServerOverrideKey, override);
    }
    notifyListeners();
  }

  void _applyServerOverride(String override) {
    final colon = override.lastIndexOf(':');
    if (colon <= 0) return;
    final h = override.substring(0, colon);
    final p = int.tryParse(override.substring(colon + 1));
    if (p != null) _transport.updateServer(host: h, port: p);
  }

  /// Send a `#filter` command composed from the current viewport, active
  /// [AprsIsFilterConfig], and the operator's subscribed named-bulletin
  /// groups.
  ///
  /// Delegates to [AprsIsFilterBuilder] for the actual string composition
  /// so the filter shape is testable in isolation (ADR-058). No-op if the
  /// transport is not connected.
  void updateFilter(LatLngBox box, {AprsIsFilterConfig? config}) {
    final cfg = config ?? _filterConfig;
    _lastBox = box;
    final line = AprsIsFilterBuilder.buildFilterLine(
      box: box,
      config: cfg,
      namedBulletinGroups: _namedBulletinGroups,
    );
    _transport.sendLine(line);
  }

  /// Replace the named-bulletin-group list used in the filter and re-send
  /// `#filter` with the same viewport so the server begins delivering
  /// bulletins for the new subscription set immediately. If no viewport is
  /// known yet (first connect with no map moves), stores the new set and
  /// defers the filter update to the next [updateFilter] call.
  ///
  /// Called from `ConnectionRegistry.loadAllSettings` and from a listener on
  /// [BulletinSubscriptionService] (ADR-058).
  void onSubscriptionsChanged(List<String> namedBulletinGroups) {
    _namedBulletinGroups = List.unmodifiable(namedBulletinGroups);
    final box = _lastBox;
    if (box != null && isConnected) updateFilter(box);
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
    List<String> namedBulletinGroups = const [],
  }) {
    return AprsIsFilterBuilder.buildDefaultFilterLine(
      lat: lat,
      lon: lon,
      config: config ?? AprsIsFilterConfig.defaultConfig,
      namedBulletinGroups: namedBulletinGroups,
    );
  }
}
