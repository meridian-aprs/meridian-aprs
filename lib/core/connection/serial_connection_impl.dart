library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ax25/ax25_encoder.dart';
import '../packet/aprs_parser.dart';
import '../transport/kiss_tnc_transport.dart';
import '../transport/serial_kiss_transport.dart';
import '../transport/tnc_config.dart';
import 'meridian_connection.dart';
import 'reconnectable_mixin.dart';

/// USB serial KISS TNC connection.
///
/// Wraps [SerialKissTransport] (one instance per connect attempt) and exposes
/// it through the [MeridianConnection] interface. AX.25 frames from the
/// transport are decoded to APRS text internally; callers only see [lines].
///
/// Reconnects automatically on error using [ReconnectableMixin] exponential
/// backoff (2 s → 4 s → 8 s → 16 s → 30 s, up to 5 fast retries then keeps
/// retrying every 30 s). This handles transient USB disconnects during TNC PTT
/// without requiring user intervention.
///
/// Call [connectWithConfig] to initiate a session. [config] is persisted to
/// SharedPreferences so it survives app restarts; [loadPersistedSettings]
/// restores it on startup without connecting.
class SerialConnection extends MeridianConnection with ReconnectableMixin {
  SerialConnection();

  static const _kBeaconingKey = 'beacon_enabled_serial_tnc';

  // ---------------------------------------------------------------------------
  // Persistent stream infrastructure
  // ---------------------------------------------------------------------------

  /// Outer [lines] stream — lives for the lifetime of this object.
  final _linesController = StreamController<String>.broadcast();

  /// Outer [connectionState] stream — same lifetime guarantee.
  final _stateController = StreamController<ConnectionStatus>.broadcast();

  ConnectionStatus _status = ConnectionStatus.disconnected;

  // ---------------------------------------------------------------------------
  // Inner transport state
  // ---------------------------------------------------------------------------

  KissTncTransport? _transport;

  StreamSubscription<Uint8List>? _frameSub;
  StreamSubscription<ConnectionStatus>? _transportStateSub;

  final _parser = AprsParser();
  bool _beaconingEnabled = true;

  TncConfig? _activeConfig;
  String? _lastErrorMessage;

  // ---------------------------------------------------------------------------
  // Test injection
  // ---------------------------------------------------------------------------

  /// Override in tests to inject a fake transport instead of a real
  /// [SerialKissTransport].
  @visibleForTesting
  KissTncTransport Function(TncConfig)? transportFactory;

  // ---------------------------------------------------------------------------
  // MeridianConnection — identity
  // ---------------------------------------------------------------------------

  @override
  String get id => 'serial_tnc';

  @override
  String get displayName => 'USB TNC';

  @override
  ConnectionType get type => ConnectionType.serialTnc;

  @override
  bool get isAvailable {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows;
  }

  // ---------------------------------------------------------------------------
  // MeridianConnection — state
  // ---------------------------------------------------------------------------

  @override
  ConnectionStatus get status {
    if (_status == ConnectionStatus.reconnecting ||
        _status == ConnectionStatus.waitingForDevice) {
      return _status;
    }
    return _transport?.currentStatus ?? _status;
  }

  @override
  Stream<ConnectionStatus> get connectionState => _stateController.stream;

  @override
  bool get isConnected => status == ConnectionStatus.connected;

  // ---------------------------------------------------------------------------
  // Serial-specific getters
  // ---------------------------------------------------------------------------

  /// The active or last-used [TncConfig].
  TncConfig? get activeConfig => _activeConfig;

  /// Human-readable error description. Non-null when [status] is
  /// [ConnectionStatus.error].
  String? get lastErrorMessage => _lastErrorMessage;

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
  Stream<String> get lines => _linesController.stream;

  @override
  Future<void> sendLine(String aprsLine) async {
    final transport = _transport;
    if (transport == null || !transport.isConnected) {
      throw StateError('SerialConnection: not connected');
    }
    final ax25Bytes = _buildAx25Bytes(aprsLine);
    if (ax25Bytes != null) {
      await transport.sendFrame(ax25Bytes);
    }
  }

  // ---------------------------------------------------------------------------
  // MeridianConnection — lifecycle
  // ---------------------------------------------------------------------------

  /// Set the target config and connect.
  ///
  /// Persists [config] to SharedPreferences for next-launch restore.
  /// On failure, sets [lastErrorMessage] and emits [ConnectionStatus.error].
  Future<void> connectWithConfig(TncConfig config) async {
    _activeConfig = config;
    _lastErrorMessage = null;
    await _saveConfig(config);
    return connect();
  }

  @override
  Future<void> connect() async {
    final config = _activeConfig;
    if (config == null) {
      throw StateError(
        'SerialConnection: no config set — call connectWithConfig() first',
      );
    }
    await _tearDownTransport();
    _buildAndAttachTransport(config);
    try {
      await _transport!.connect();
    } catch (e) {
      _lastErrorMessage = _serialErrorMessage(e.toString(), config.port);
      _emitStatus(ConnectionStatus.error);
      notifyListeners();
    }
  }

  @override
  Future<void> disconnect() async {
    cancelReconnect();
    await _tearDownTransport();
    _emitStatus(ConnectionStatus.disconnected);
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    cancelReconnect();
    await _tearDownTransport();
    await _linesController.close();
    await _stateController.close();
    super.dispose();
  }

  @override
  Future<void> loadPersistedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _beaconingEnabled = prefs.getBool(_kBeaconingKey) ?? true;
    final map = {
      for (final key in prefs.getKeys())
        if (key.startsWith('tnc_')) key: prefs.get(key),
    };
    _activeConfig = TncConfig.fromPrefsMap(map);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Serial-specific helpers
  // ---------------------------------------------------------------------------

  /// Returns available serial port names. Empty on non-desktop platforms or
  /// when the native serial library cannot be loaded (e.g. in test
  /// environments without a real serial driver installed).
  List<String> availablePorts() {
    try {
      return SerialKissTransport.availablePorts();
    } catch (_) {
      return const [];
    }
  }

  // ---------------------------------------------------------------------------
  // Internal — transport management
  // ---------------------------------------------------------------------------

  KissTncTransport _buildTransport(TncConfig config) =>
      transportFactory?.call(config) ?? SerialKissTransport(config);

  void _buildAndAttachTransport(TncConfig config) {
    final t = _buildTransport(config);
    _transport = t;

    _transportStateSub = t.connectionState.listen(_onTransportStatus);
    _frameSub = t.frameStream.listen(_onFrame);
  }

  Future<void> _tearDownTransport() async {
    await _transportStateSub?.cancel();
    _transportStateSub = null;
    await _frameSub?.cancel();
    _frameSub = null;
    try {
      await _transport?.disconnect();
    } catch (_) {}
    _transport = null;
  }

  void _onTransportStatus(ConnectionStatus s) {
    _emitStatus(s);
    notifyListeners();

    if (s == ConnectionStatus.connected) {
      markSessionConnected();
    } else if (s == ConnectionStatus.error && shouldAttemptReconnect()) {
      scheduleReconnect(_emitStatus);
    }
  }

  // ---------------------------------------------------------------------------
  // ReconnectableMixin — reconnect implementation
  // ---------------------------------------------------------------------------

  @override
  Future<void> doAttemptReconnect() async {
    final config = _activeConfig;
    if (config == null) return; // disconnect() was called

    debugPrint('SerialConnection: attempting reconnect on ${config.port}');
    await _tearDownTransport();
    if (_activeConfig == null) return; // disconnect() called during teardown

    // Transport construction itself can throw when the USB device hasn't
    // re-enumerated yet (ENOENT / errno=2). Catch this separately so we
    // schedule the next backoff retry rather than propagating as unhandled.
    try {
      _buildAndAttachTransport(config);
    } catch (e) {
      debugPrint('SerialConnection: port not yet available — $e');
      if (shouldAttemptReconnect()) scheduleReconnect(_emitStatus);
      return;
    }

    try {
      await _transport!.connect();
    } catch (e) {
      debugPrint('SerialConnection: reconnect attempt failed: $e');
      // Transport already emitted error → _onTransportStatus → scheduleReconnect
    }
  }

  void _onFrame(Uint8List frameBytes) {
    final packet = _parser.parseFrame(frameBytes);
    if (packet.rawLine.isNotEmpty && !_linesController.isClosed) {
      _linesController.add(packet.rawLine);
    }
  }

  void _emitStatus(ConnectionStatus s) {
    _status = s;
    if (!_stateController.isClosed) {
      _stateController.add(s);
    }
  }

  // ---------------------------------------------------------------------------
  // Internal — AX.25 encoding
  // ---------------------------------------------------------------------------

  Uint8List? _buildAx25Bytes(String aprsLine) {
    final gtIdx = aprsLine.indexOf('>');
    final colonIdx = aprsLine.indexOf(':');
    if (gtIdx < 0 || colonIdx < 0 || colonIdx <= gtIdx) return null;

    final sourceRaw = aprsLine.substring(0, gtIdx).trim();
    final infoField = aprsLine.substring(colonIdx + 1);

    final sourceParts = sourceRaw.split('-');
    final callsign = sourceParts[0].toUpperCase();
    final ssid = sourceParts.length > 1 ? int.tryParse(sourceParts[1]) ?? 0 : 0;

    final frame = Ax25Encoder.buildAprsFrame(
      sourceCallsign: callsign,
      sourceSsid: ssid,
      infoField: infoField,
    );
    return Ax25Encoder.encodeUiFrame(frame);
  }

  // ---------------------------------------------------------------------------
  // Internal — persistence
  // ---------------------------------------------------------------------------

  Future<void> _saveConfig(TncConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in config.toPrefsMap().entries) {
      final value = entry.value;
      if (value is String) await prefs.setString(entry.key, value);
      if (value is int) await prefs.setInt(entry.key, value);
      if (value is bool) await prefs.setBool(entry.key, value);
    }
  }

  String _serialErrorMessage(String error, String port) {
    final lower = error.toLowerCase();
    if (lower.contains('permission') ||
        lower.contains('access denied') ||
        lower.contains('eacces')) {
      if (defaultTargetPlatform == TargetPlatform.linux) {
        return 'Permission denied on $port.\n'
            'Add your user to the dialout group:\n'
            '  sudo usermod -aG dialout \$USER\n'
            'Then log out and back in.';
      } else if (defaultTargetPlatform == TargetPlatform.macOS) {
        return 'Permission denied on $port.\n'
            'Grant serial port access in:\n'
            '  System Settings › Privacy & Security';
      }
      return 'Permission denied on $port. Check your serial port permissions.';
    }
    if (lower.contains('no such file') ||
        lower.contains('not found') ||
        lower.contains('enoent')) {
      return 'Port $port not found. Is the TNC plugged in?';
    }
    return 'Could not connect to $port: $error';
  }
}
