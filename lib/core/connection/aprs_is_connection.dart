import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import '../transport/aprs_is_transport.dart';
import 'meridian_connection.dart';

/// APRS-IS connection over TCP (or WebSocket proxy on web — see ADR-004).
///
/// Wraps [AprsIsTransport] and exposes it through the [MeridianConnection]
/// interface. Beaconing is enabled by default and persisted to
/// SharedPreferences under the key `beacon_enabled_aprs_is`.
class AprsIsConnection extends MeridianConnection {
  AprsIsConnection(this._transport);

  final AprsIsTransport _transport;

  static const _kBeaconingKey = 'beacon_enabled_aprs_is';

  bool _beaconingEnabled = true;

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
    await _transport.connect();
    notifyListeners();
  }

  @override
  Future<void> disconnect() async {
    await _transport.disconnect();
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    await _transport.dispose();
    super.dispose();
  }

  @override
  Future<void> loadPersistedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _beaconingEnabled = prefs.getBool(_kBeaconingKey) ?? true;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // APRS-IS specific API
  // ---------------------------------------------------------------------------

  /// Update the login and filter lines used on the next [connect] call.
  ///
  /// Safe to call while disconnected. Has no effect on an active connection —
  /// reconnect to apply the new credentials.
  void updateCredentials({required String loginLine, String? filterLine}) {
    _transport.updateCredentials(loginLine: loginLine, filterLine: filterLine);
  }

  /// Send a `#filter` command to the current connection.
  ///
  /// No-op if the transport is not connected.
  void updateFilter(double lat, double lon, {int radiusKm = 150}) {
    final line =
        '#filter r/${lat.toStringAsFixed(2)}/${lon.toStringAsFixed(2)}/$radiusKm\r\n';
    _transport.sendLine(line);
  }
}
