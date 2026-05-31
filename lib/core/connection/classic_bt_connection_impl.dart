library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ax25/ax25_encoder.dart';
import '../packet/aprs_parser.dart';
import '../transport/classic_bt_spp_channel.dart';
import '../transport/classic_bt_tnc_transport.dart';
import '../transport/kiss_tnc_transport.dart';
import '../util/clock.dart';
import 'meridian_connection.dart';
import 'reconnectable_mixin.dart';

/// Classic Bluetooth SPP (RFCOMM) KISS TNC connection (ADR-069).
///
/// The serial twin of [SerialConnection] — a raw byte stream through the
/// transport-agnostic `KissFramer`, **not** the BLE/GATT model. Wraps
/// [ClassicBtTncTransport] (one instance per connect attempt) and exposes it
/// through the [MeridianConnection] interface; AX.25 frames are decoded to APRS
/// text internally, callers only see [lines].
///
/// Reconnects via [ReconnectableMixin] active polling (like Serial, not BLE's
/// OS-managed background scan): exponential backoff 2 s → 4 s → 8 s → 16 s →
/// 30 s, up to 5 fast retries, then keeps retrying every 30 s.
///
/// Owns **one** long-lived [ClassicBtSppChannel] for the connection's lifetime.
/// The native bridge's RX [EventChannel] is single-sink; sharing one channel
/// across per-connect transports avoids the listener race that would otherwise
/// drop the sink on reconnect.
///
/// Android only in v0.21 (Phase 3 widens to desktop). iOS is excluded by
/// platform restriction (Classic BT requires MFi/ExternalAccessory).
class ClassicBtConnection extends MeridianConnection with ReconnectableMixin {
  ClassicBtConnection({
    Clock clock = DateTime.now,
    ClassicBtSppChannel? channel,
  }) : _clock = clock,
       _channel = channel ?? ClassicBtSppChannel();

  final Clock _clock;
  final ClassicBtSppChannel _channel;

  static const _kBeaconingKey = 'beacon_enabled_classic_bt_tnc';
  static const _kAddressKey = 'classic_bt_address';
  static const _kNameKey = 'classic_bt_name';

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

  /// Bluetooth MAC address of the target device, retained so reconnect attempts
  /// target the same device. Null when no device is set.
  String? _address;

  /// Friendly device name (from the paired-device list) for diagnostics and UI.
  String? _deviceName;

  String? _lastErrorMessage;

  // ---------------------------------------------------------------------------
  // Test injection
  // ---------------------------------------------------------------------------

  /// Override in tests to inject a fake transport instead of a real
  /// [ClassicBtTncTransport]. Receives the target device address.
  @visibleForTesting
  KissTncTransport Function(String address)? transportFactory;

  // ---------------------------------------------------------------------------
  // MeridianConnection — identity
  // ---------------------------------------------------------------------------

  @override
  String get id => 'classic_bt_tnc';

  @override
  String get displayName => 'Classic BT';

  @override
  ConnectionType get type => ConnectionType.classicBtTnc;

  @override
  bool get isAvailable {
    if (kIsWeb) return false;
    // Android only in v0.21. iOS is excluded by platform restriction (MFi).
    // Phase 3 widens this to Linux/macOS/Windows.
    return defaultTargetPlatform == TargetPlatform.android;
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
  // Classic-BT-specific getters
  // ---------------------------------------------------------------------------

  /// MAC address of the active or last-used device.
  String? get deviceAddress => _address;

  /// Friendly name of the active or last-used device.
  String? get deviceName => _deviceName;

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
  Future<void> sendLine(String aprsLine, {List<String>? digipeaterPath}) async {
    final transport = _transport;
    if (transport == null || !transport.isConnected) {
      throw StateError('ClassicBtConnection: not connected');
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
  /// Persists [address] / [name] to SharedPreferences for next-launch restore.
  /// On failure, sets [lastErrorMessage] and emits [ConnectionStatus.error].
  Future<void> connectToDevice(String address, {String? name}) async {
    _address = address;
    _deviceName = name;
    _lastErrorMessage = null;
    await _saveDevice(address, name);
    return connect();
  }

  @override
  Future<void> connect() async {
    final address = _address;
    if (address == null) {
      throw StateError(
        'ClassicBtConnection: no device set — call connectToDevice() first',
      );
    }
    await _tearDownTransport();
    _buildAndAttachTransport(address);
    try {
      await _transport!.connect();
    } catch (e) {
      _lastErrorMessage = 'Could not connect to ${_deviceName ?? address}';
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
    await _channel.dispose();
    await _linesController.close();
    await _stateController.close();
    super.dispose();
  }

  @override
  Future<void> loadPersistedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _beaconingEnabled = prefs.getBool(_kBeaconingKey) ?? true;
    _address = prefs.getString(_kAddressKey);
    _deviceName = prefs.getString(_kNameKey);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Classic-BT-specific helpers
  // ---------------------------------------------------------------------------

  /// Returns the already-paired (OS-bonded) Classic BT devices. Pairing itself
  /// is owned by Android Bluetooth settings — there is no in-app discovery.
  ///
  /// May throw a [PlatformException] if `BLUETOOTH_CONNECT` is not granted; the
  /// caller is expected to request the runtime permission first.
  Future<List<ClassicBtPairedDevice>> pairedDevices() =>
      ClassicBtTncTransport.pairedDevices();

  // ---------------------------------------------------------------------------
  // Internal — transport management
  // ---------------------------------------------------------------------------

  KissTncTransport _buildTransport(String address) =>
      transportFactory?.call(address) ??
      ClassicBtTncTransport(address, channel: _channel);

  void _buildAndAttachTransport(String address) {
    final t = _buildTransport(address);
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
    if (s == ConnectionStatus.error) {
      _lastErrorMessage ??=
          'Could not connect to ${_deviceName ?? _address ?? 'Classic BT'}';
    }
    _emitStatus(s);
    notifyListeners();

    if (s == ConnectionStatus.connected) {
      _lastErrorMessage = null;
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
    final address = _address;
    if (address == null) return; // disconnect() was called

    debugPrint('ClassicBtConnection: attempting reconnect to $address');
    await _tearDownTransport();
    if (_address == null) return; // disconnect() called during teardown

    _buildAndAttachTransport(address);
    try {
      await _transport!.connect();
    } catch (e) {
      debugPrint('ClassicBtConnection: reconnect attempt failed: $e');
      // Transport already emitted error → _onTransportStatus → scheduleReconnect
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
  // Internal — persistence
  // ---------------------------------------------------------------------------

  Future<void> _saveDevice(String address, String? name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAddressKey, address);
    if (name != null) {
      await prefs.setString(_kNameKey, name);
    } else {
      await prefs.remove(_kNameKey);
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
