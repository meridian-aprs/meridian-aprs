import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'aprs_transport.dart' show ConnectionStatus;
import 'ble_tnc_transport.dart';
import 'kiss_tnc_transport.dart';
import 'serial_kiss_transport.dart';
import 'serial_port_adapter.dart';
import 'tnc_config.dart';

export 'aprs_transport.dart' show ConnectionStatus;

/// Identifies which transport type is currently active.
enum TransportType { none, serial, ble }

/// Manages the lifecycle of the currently active [KissTncTransport].
///
/// Holds at most one active transport at a time. Switching transports
/// disconnects the current one first. Exposes [frameStream] and
/// [connectionState] as re-published streams so callers don't need to
/// re-subscribe when the underlying transport changes.
///
/// **BLE auto-reconnect:** after a BLE session is established and then drops
/// unexpectedly, [TransportManager] automatically attempts to reconnect using
/// exponential backoff (2 s → 4 s → 8 s → 16 s → 30 s, up to
/// [_maxRetries] attempts). Reconnect emits [ConnectionStatus.reconnecting]
/// between attempts so the UI can show progress. Calling [disconnect]
/// cancels any pending retry.
///
/// Register as a [ChangeNotifier] (via [TncService]) so the UI can react
/// to transport changes.
class TransportManager extends ChangeNotifier {
  // ---------------------------------------------------------------------------
  // BLE reconnect parameters
  // ---------------------------------------------------------------------------

  static const int _maxRetries = 5;
  static const Duration _baseRetryDelay = Duration(seconds: 2);
  static const Duration _maxRetryDelay = Duration(seconds: 30);

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  KissTncTransport? _active;
  TransportType _activeType = TransportType.none;

  StreamSubscription<ConnectionStatus>? _stateSub;
  StreamSubscription<Uint8List>? _frameSub;

  final _stateController = StreamController<ConnectionStatus>.broadcast();
  final _framesController = StreamController<Uint8List>.broadcast();

  // BLE reconnect state
  BluetoothDevice? _lastBleDevice;
  bool _bleSessionConnected =
      false; // true once link has been connected at least once
  int _retryAttempt = 0;
  Timer? _retryTimer;
  bool _inWaitingPhase = false; // true while OS background connect is pending

  /// Optional factory for creating [KissTncTransport] from a [BluetoothDevice].
  /// Defaults to [BleTncTransport]. Override in tests via [bleTransportFactory].
  @visibleForTesting
  KissTncTransport Function(BluetoothDevice)? bleTransportFactory;

  // ---------------------------------------------------------------------------
  // Public read API
  // ---------------------------------------------------------------------------

  KissTncTransport? get activeTransport => _active;
  TransportType get activeType => _activeType;
  bool get isConnected => _active?.isConnected ?? false;
  ConnectionStatus get currentStatus =>
      _active?.currentStatus ?? ConnectionStatus.disconnected;

  /// Stream of [ConnectionStatus] from whichever transport is active.
  Stream<ConnectionStatus> get connectionState => _stateController.stream;

  /// Stream of raw AX.25 frame payloads from whichever transport is active.
  Stream<Uint8List> get frameStream => _framesController.stream;

  // ---------------------------------------------------------------------------
  // Connect / disconnect
  // ---------------------------------------------------------------------------

  /// Connect using USB serial with [config].
  ///
  /// Disconnects any currently active transport first.
  /// Pass [adapter] to inject a fake for tests.
  Future<void> connectSerial(
    TncConfig config, {
    SerialPortAdapter? adapter,
  }) async {
    await disconnect();
    final transport = SerialKissTransport(config, adapter: adapter);
    _attach(transport, TransportType.serial);
    await transport.connect();
  }

  /// Connect to a BLE TNC device.
  ///
  /// Disconnects any currently active transport first. On unexpected
  /// disconnection, the manager will attempt to reconnect automatically
  /// (see class-level docs). Call [disconnect] to cancel any pending retries.
  Future<void> connectBle(BluetoothDevice device) async {
    await disconnect(); // clears all retry state
    _lastBleDevice = device;
    _bleSessionConnected = false;
    _retryAttempt = 0;
    final transport = _buildBleTransport(device);
    _attach(transport, TransportType.ble);
    await transport.connect();
  }

  /// Disconnect the active transport and release resources.
  ///
  /// Also cancels any pending BLE reconnect attempt.
  Future<void> disconnect() async {
    // Cancel any pending BLE reconnect before tearing down the transport.
    _retryTimer?.cancel();
    _retryTimer = null;
    _lastBleDevice = null;
    _bleSessionConnected = false;
    _retryAttempt = 0;
    _inWaitingPhase = false;

    if (_active == null) return;
    await _stateSub?.cancel();
    _stateSub = null;
    await _frameSub?.cancel();
    _frameSub = null;
    await _active!.disconnect();
    _active = null;
    _activeType = TransportType.none;
    _stateController.add(ConnectionStatus.disconnected);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Internal — transport attachment
  // ---------------------------------------------------------------------------

  void _attach(KissTncTransport t, TransportType type) {
    _active = t;
    _activeType = type;
    _stateSub = t.connectionState.listen((s) {
      _stateController.add(s);
      notifyListeners();
      if (s == ConnectionStatus.connected && type == TransportType.ble) {
        _bleSessionConnected = true;
        _retryAttempt = 0; // reset backoff on successful (re)connect
      }
      if (s == ConnectionStatus.error &&
          type == TransportType.ble &&
          _lastBleDevice != null &&
          _bleSessionConnected &&
          _retryTimer == null &&
          !_inWaitingPhase) {
        _scheduleReconnect();
      }
    });
    _frameSub = t.frameStream.listen(_framesController.add);
  }

  // ---------------------------------------------------------------------------
  // Internal — BLE reconnect
  // ---------------------------------------------------------------------------

  KissTncTransport _buildBleTransport(BluetoothDevice device) =>
      bleTransportFactory?.call(device) ?? BleTncTransport(device);

  void _scheduleReconnect() {
    if (_retryAttempt >= _maxRetries) {
      debugPrint(
        'TransportManager: BLE fast-retries exhausted — switching to OS auto-connect',
      );
      _enterWaitingPhase();
      return;
    }

    _retryAttempt++;
    final delay = _retryDelay(_retryAttempt);
    debugPrint(
      'TransportManager: scheduling BLE reconnect attempt '
      '$_retryAttempt/$_maxRetries in ${delay.inSeconds}s',
    );
    _stateController.add(ConnectionStatus.reconnecting);
    notifyListeners();
    _retryTimer = Timer(delay, _attemptReconnect);
  }

  Duration _retryDelay(int attempt) {
    // Exponential backoff: 2 s, 4 s, 8 s, 16 s, 30 s (capped).
    final ms = _baseRetryDelay.inMilliseconds * (1 << (attempt - 1));
    return Duration(milliseconds: ms.clamp(0, _maxRetryDelay.inMilliseconds));
  }

  Future<void> _attemptReconnect() async {
    _retryTimer = null; // timer has fired; null so listener can schedule next

    final device = _lastBleDevice;
    if (device == null) return; // user called disconnect() before timer fired

    debugPrint(
      'TransportManager: BLE reconnect attempt $_retryAttempt/$_maxRetries',
    );

    // Tear down the dead transport without clearing reconnect state.
    await _stateSub?.cancel();
    _stateSub = null;
    await _frameSub?.cancel();
    _frameSub = null;
    try {
      await _active?.disconnect();
    } catch (_) {}
    _active = null;
    _activeType = TransportType.none;

    final transport = _buildBleTransport(device);
    _attach(transport, TransportType.ble);

    // Guard: disconnect() may have been called while we were tearing down the
    // old transport (_active was null so disconnect() returned early). Check
    // _lastBleDevice again — if it was cleared, abort the new transport now.
    if (_lastBleDevice == null) {
      await _stateSub?.cancel();
      _stateSub = null;
      await _frameSub?.cancel();
      _frameSub = null;
      try {
        await transport.disconnect();
      } catch (_) {}
      _active = null;
      _activeType = TransportType.none;
      return;
    }

    try {
      await transport.connect();
      // Success path — _bleSessionConnected and _retryAttempt reset in listener.
    } catch (e) {
      debugPrint(
        'TransportManager: BLE reconnect attempt $_retryAttempt failed: $e',
      );
      // The transport already emitted ConnectionStatus.error, which triggered
      // _scheduleReconnect via the listener. Nothing more to do here.
    }
  }

  // ---------------------------------------------------------------------------
  // Internal — BLE waiting phase (OS-managed auto-connect)
  // ---------------------------------------------------------------------------

  /// Switches to OS-managed background scanning after fast retries exhaust.
  ///
  /// Emits [ConnectionStatus.waitingForDevice] and hands the reconnection
  /// attempt to the OS via [KissTncTransport.connectBackground]. The OS will
  /// reconnect whenever the device comes back in range (up to one hour).
  /// Calling [disconnect] cancels this phase immediately.
  void _enterWaitingPhase() {
    final device = _lastBleDevice;
    if (device == null) return;

    _inWaitingPhase = true;
    _retryAttempt = 0;
    debugPrint('TransportManager: entering OS auto-connect waiting phase');
    _stateController.add(ConnectionStatus.waitingForDevice);
    notifyListeners();
    _doWaitingPhaseConnect(device);
  }

  Future<void> _doWaitingPhaseConnect(BluetoothDevice device) async {
    // Tear down the dead transport without clearing reconnect state.
    await _stateSub?.cancel();
    _stateSub = null;
    await _frameSub?.cancel();
    _frameSub = null;
    try {
      await _active?.disconnect();
    } catch (_) {}
    _active = null;
    _activeType = TransportType.none;

    if (_lastBleDevice == null) return; // disconnect() was called

    final transport = _buildBleTransport(device);
    _attach(transport, TransportType.ble);

    // Same race guard as _attemptReconnect: disconnect() may have cleared
    // _lastBleDevice while _active was null during teardown above.
    if (_lastBleDevice == null) {
      await _stateSub?.cancel();
      _stateSub = null;
      await _frameSub?.cancel();
      _frameSub = null;
      try {
        await transport.disconnect();
      } catch (_) {}
      _active = null;
      _activeType = TransportType.none;
      return;
    }

    try {
      await transport.connectBackground();
      // Success — _bleSessionConnected and _retryAttempt reset via listener.
      _inWaitingPhase = false;
    } catch (e) {
      _inWaitingPhase = false;
      if (_lastBleDevice == null) return; // intentional disconnect, no error
      debugPrint(
        'TransportManager: OS auto-connect failed (device may be off): $e',
      );
      _lastBleDevice = null;
      _stateController.add(ConnectionStatus.error);
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // dispose
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    disconnect();
    _stateController.close();
    _framesController.close();
    super.dispose();
  }
}
