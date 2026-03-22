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
/// Register as a [ChangeNotifier] (via [TncService]) so the UI can react
/// to transport changes.
class TransportManager extends ChangeNotifier {
  KissTncTransport? _active;
  TransportType _activeType = TransportType.none;

  StreamSubscription<ConnectionStatus>? _stateSub;
  StreamSubscription<Uint8List>? _frameSub;

  final _stateController = StreamController<ConnectionStatus>.broadcast();
  final _framesController = StreamController<Uint8List>.broadcast();

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
  Future<void> connectSerial(TncConfig config, {SerialPortAdapter? adapter}) async {
    await disconnect();
    final transport = SerialKissTransport(config, adapter: adapter);
    _attach(transport, TransportType.serial);
    await transport.connect();
  }

  /// Connect to a BLE TNC device.
  ///
  /// Disconnects any currently active transport first.
  Future<void> connectBle(BluetoothDevice device) async {
    await disconnect();
    final transport = BleTncTransport(device);
    _attach(transport, TransportType.ble);
    await transport.connect();
  }

  /// Disconnect the active transport and release resources.
  Future<void> disconnect() async {
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
  // Internal
  // ---------------------------------------------------------------------------

  void _attach(KissTncTransport t, TransportType type) {
    _active = t;
    _activeType = type;
    _stateSub = t.connectionState.listen((s) {
      _stateController.add(s);
      notifyListeners();
    });
    _frameSub = t.frameStream.listen(_framesController.add);
  }

  @override
  void dispose() {
    disconnect();
    _stateController.close();
    _framesController.close();
    super.dispose();
  }
}
