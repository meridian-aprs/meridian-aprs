library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ax25/ax25_encoder.dart';
import '../packet/aprs_parser.dart';
import '../transport/ble_constants.dart';
import '../transport/ble_diagnostics.dart';
import '../transport/ble_tnc_transport.dart';
import '../transport/kiss_tnc_transport.dart';
import '../util/clock.dart';
import 'meridian_connection.dart';
import 'reconnectable_mixin.dart';

/// BLE KISS TNC connection.
///
/// Wraps [BleTncTransport] (one instance per connect attempt) and exposes it
/// through the [MeridianConnection] interface. AX.25 frames from the transport
/// are decoded to APRS text internally; callers only see [lines].
///
/// Automatic reconnection uses [ReconnectableMixin] with exponential backoff
/// for fast retries (2 s → 4 s → 8 s → 16 s → 30 s), then falls back to
/// OS-managed background scanning via [BleTncTransport.connectBackground].
///
/// Call [connectToDevice] to initiate a session with a specific BLE device.
/// Calling [connect] after [connectToDevice] re-uses the stored device.
class BleConnection extends MeridianConnection with ReconnectableMixin {
  BleConnection({Clock clock = DateTime.now}) : _clock = clock;

  final Clock _clock;

  static const _kBeaconingKey = 'beacon_enabled_ble_tnc';

  // ---------------------------------------------------------------------------
  // Persistent stream infrastructure
  // ---------------------------------------------------------------------------

  /// Outer [lines] stream — lives for the lifetime of this connection object,
  /// even as the inner [BleTncTransport] is torn down and recreated on retries.
  final _linesController = StreamController<String>.broadcast();

  /// Outer [connectionState] stream — same lifetime guarantee.
  final _stateController = StreamController<ConnectionStatus>.broadcast();

  ConnectionStatus _status = ConnectionStatus.disconnected;

  // ---------------------------------------------------------------------------
  // Inner transport state
  // ---------------------------------------------------------------------------

  /// Stable platform device id of the target peripheral, retained so automatic
  /// reconnect attempts target the same device. Null when no device is set.
  String? _deviceId;

  /// Friendly device name (from the scanner advertisement) for diagnostics.
  String? _deviceName;

  /// Optional family hint for the active session, supplied by the scanner via
  /// [connectToDevice]. When null, the transport autodetects the family from
  /// the discovered service list — robust across cold reconnects where the
  /// scan advertisement isn't available.
  BleKissFamily? _family;

  KissTncTransport? _transport;

  StreamSubscription<Uint8List>? _frameSub;
  StreamSubscription<ConnectionStatus>? _transportStateSub;

  final _parser = AprsParser();
  bool _beaconingEnabled = true;

  // ---------------------------------------------------------------------------
  // Test injection
  // ---------------------------------------------------------------------------

  /// Override in tests to inject a [FakeKissTncTransport] instead of a real
  /// [BleTncTransport]. Receives the target device id.
  @visibleForTesting
  KissTncTransport Function(String deviceId)? transportFactory;

  // ---------------------------------------------------------------------------
  // MeridianConnection — identity
  // ---------------------------------------------------------------------------

  @override
  String get id => 'ble_tnc';

  @override
  String get displayName => 'BLE TNC';

  @override
  ConnectionType get type => ConnectionType.bleTnc;

  @override
  bool get isAvailable {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  // ---------------------------------------------------------------------------
  // MeridianConnection — state
  // ---------------------------------------------------------------------------

  /// Current status.
  ///
  /// Reconnecting/waitingForDevice states are managed by this connection object
  /// (set by [ReconnectableMixin]); the underlying transport never enters these
  /// states. When in those states, return [_status] directly.
  ///
  /// For all other states, delegate to the live transport's synchronous
  /// [currentStatus] so callers see [ConnectionStatus.connected] immediately
  /// after [connect] completes — without waiting for async stream delivery.
  /// Falls back to [_status] when no transport is active.
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
  Future<void> sendLine(String aprsLine, {List<String>? digipeaterPath}) async {
    final transport = _transport;
    if (transport == null || !transport.isConnected) {
      throw StateError('BleConnection: not connected');
    }
    final ax25Bytes = _buildAx25Bytes(aprsLine, digipeaterPath: digipeaterPath);
    if (ax25Bytes != null) {
      await transport.sendFrame(ax25Bytes);
    }
  }

  // ---------------------------------------------------------------------------
  // MeridianConnection — lifecycle
  // ---------------------------------------------------------------------------

  /// Set the target device and connect.
  ///
  /// Stores [deviceId] so that automatic reconnect attempts use the same
  /// device. [deviceName] is an optional friendly label used only for
  /// diagnostics. [family] is an optional hint about which BLE-KISS GATT
  /// family this device implements — supply it from the scanner when known
  /// from advertised service UUIDs to skip a round of post-discovery
  /// autodetection.
  Future<void> connectToDevice(
    String deviceId, {
    String? deviceName,
    BleKissFamily? family,
  }) {
    _deviceId = deviceId;
    _deviceName = deviceName;
    _family = family;
    return connect();
  }

  @override
  Future<void> connect() async {
    final deviceId = _deviceId;
    if (deviceId == null) {
      throw StateError(
        'BleConnection: no device set — call connectToDevice() first',
      );
    }
    // Internal: a fresh connect() supersedes any prior session — the teardown
    // is plumbing, not a user-initiated disconnect, and the diagnostics log
    // should reflect that.
    await _tearDownTransport(internal: true);
    _buildAndAttachTransport(deviceId);
    await _transport!.connect();
  }

  @override
  Future<void> disconnect() async {
    cancelReconnect();
    _deviceId = null;
    _deviceName = null;
    _family = null;
    await _tearDownTransport(internal: false);
    _emitStatus(ConnectionStatus.disconnected);
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    cancelReconnect();
    await _tearDownTransport(internal: true);
    await _linesController.close();
    await _stateController.close();
    super.dispose();
  }

  @override
  Future<void> loadPersistedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _beaconingEnabled = prefs.getBool(_kBeaconingKey) ?? true;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // ReconnectableMixin — reconnect implementation
  // ---------------------------------------------------------------------------

  @override
  Future<void> doAttemptReconnect() async {
    final deviceId = _deviceId;
    if (deviceId == null) return; // disconnect() was called

    final label = _deviceName ?? deviceId;
    debugPrint('BleConnection: attempting reconnect to $label');
    BleDiagnostics.I.log(BleEventKind.reconnectAttempt, 'device=$label');
    await _tearDownTransport(internal: true);
    if (_deviceId == null) return; // disconnect() called during teardown

    _buildAndAttachTransport(deviceId);
    try {
      await _transport!.connect();
    } catch (e) {
      debugPrint('BleConnection: reconnect attempt failed: $e');
      // The transport already emitted error, which triggers _onTransportStatus
      // → scheduleReconnect again.
    }
  }

  @override
  @protected
  Future<void> doWaitingPhaseReconnect() async {
    final deviceId = _deviceId;
    if (deviceId == null) return;

    final label = _deviceName ?? deviceId;
    debugPrint(
      'BleConnection: entering OS auto-connect waiting phase for $label',
    );
    BleDiagnostics.I.log(BleEventKind.waitingPhase, 'device=$label');
    await _tearDownTransport(internal: true);
    if (_deviceId == null) return;

    _buildAndAttachTransport(deviceId);
    if (_deviceId == null) {
      await _tearDownTransport(internal: true);
      return;
    }

    try {
      await _transport!.connectBackground();
    } catch (e) {
      if (_deviceId == null) return; // intentional disconnect, no error
      debugPrint(
        'BleConnection: OS auto-connect failed (device may be off): $e',
      );
      _deviceId = null;
      _emitStatus(ConnectionStatus.error);
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Internal — transport management
  // ---------------------------------------------------------------------------

  KissTncTransport _buildTransport(String deviceId) =>
      transportFactory?.call(deviceId) ??
      BleTncTransport(deviceId, deviceName: _deviceName, family: _family);

  void _buildAndAttachTransport(String deviceId) {
    final t = _buildTransport(deviceId);
    _transport = t;

    _transportStateSub = t.connectionState.listen(_onTransportStatus);
    _frameSub = t.frameStream.listen(_onFrame);
  }

  Future<void> _tearDownTransport({required bool internal}) async {
    await _transportStateSub?.cancel();
    _transportStateSub = null;
    await _frameSub?.cancel();
    _frameSub = null;
    final t = _transport;
    if (internal && t is BleTncTransport) {
      // Tag the next disconnect as an internal teardown so the diagnostics
      // log distinguishes reconnect cycles from a real user disconnect.
      t.markInternalTeardown();
    }
    try {
      await _transport?.disconnect();
    } catch (_) {}
    _transport = null;
  }

  void _onTransportStatus(ConnectionStatus s) {
    _emitStatus(s);
    notifyListeners();

    if (s == ConnectionStatus.connected) {
      BleDiagnostics.I.log(BleEventKind.sessionConnected);
      markSessionConnected();
    } else if (s == ConnectionStatus.error &&
        shouldAttemptReconnect() &&
        _deviceId != null) {
      BleDiagnostics.I.log(BleEventKind.reconnectScheduled);
      scheduleReconnect(_emitStatus);
    }
  }

  void _onFrame(Uint8List frameBytes) {
    final packet = _parser.parseFrame(frameBytes, receivedAt: _clock().toUtc());
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

  Uint8List? _buildAx25Bytes(String aprsLine, {List<String>? digipeaterPath}) {
    final gtIdx = aprsLine.indexOf('>');
    final colonIdx = aprsLine.indexOf(':');
    if (gtIdx < 0 || colonIdx < 0 || colonIdx <= gtIdx) return null;

    final sourceRaw = aprsLine.substring(0, gtIdx).trim();
    final infoField = aprsLine.substring(colonIdx + 1);

    final sourceParts = sourceRaw.split('-');
    final callsign = sourceParts[0].toUpperCase();
    final ssid = sourceParts.length > 1 ? int.tryParse(sourceParts[1]) ?? 0 : 0;

    final frame = digipeaterPath != null && digipeaterPath.isNotEmpty
        ? Ax25Encoder.buildAprsFrame(
            sourceCallsign: callsign,
            sourceSsid: ssid,
            digipeaterAliases: digipeaterPath,
            infoField: infoField,
          )
        : Ax25Encoder.buildAprsFrame(
            sourceCallsign: callsign,
            sourceSsid: ssid,
            infoField: infoField,
          );
    return Ax25Encoder.encodeUiFrame(frame);
  }
}
