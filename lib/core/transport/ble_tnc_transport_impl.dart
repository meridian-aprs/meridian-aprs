library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'aprs_transport.dart' show ConnectionStatus;
import 'ble_constants.dart';
import 'kiss_framer.dart';
import 'kiss_tnc_transport.dart';

// ---------------------------------------------------------------------------
// Testability abstraction
// ---------------------------------------------------------------------------

/// Thin wrapper around a [BluetoothDevice] for test injection.
///
/// Production code uses [DefaultBleDeviceAdapter]. Tests inject a fake.
abstract interface class BleDeviceAdapter {
  Future<void> connect({int? mtu, Duration timeout});
  Future<void> disconnect();
  Future<int> requestMtu(int desired);
  int get mtu;
  Future<List<BluetoothService>> discoverServices();
  Stream<BluetoothConnectionState> get connectionState;
  String get platformName;
}

/// Production [BleDeviceAdapter] backed by a [BluetoothDevice].
class DefaultBleDeviceAdapter implements BleDeviceAdapter {
  DefaultBleDeviceAdapter(this._device);

  final BluetoothDevice _device;

  @override
  Future<void> connect({int? mtu, Duration timeout = const Duration(seconds: 15)}) =>
      _device.connect(mtu: mtu, timeout: timeout, autoConnect: false);

  @override
  Future<void> disconnect() => _device.disconnect();

  @override
  Future<int> requestMtu(int desired) => _device.requestMtu(desired);

  @override
  int get mtu => _device.mtuNow;

  @override
  Future<List<BluetoothService>> discoverServices() => _device.discoverServices();

  @override
  Stream<BluetoothConnectionState> get connectionState => _device.connectionState;

  @override
  String get platformName => _device.platformName;
}

// ---------------------------------------------------------------------------
// BleTncTransport
// ---------------------------------------------------------------------------

/// BLE KISS TNC transport.
///
/// Implements [KissTncTransport], emitting raw AX.25 frame payloads on
/// [frameStream]. Connects to Mobilinkd-compatible BLE TNCs via a UART-
/// over-BLE GATT service.
///
/// Connection flow:
///   scan → connect → requestMtu → discoverServices
///   → subscribe to TX characteristic → ready
///
/// Incoming BLE chunks are reassembled into complete KISS frames by the
/// existing [KissFramer]. Outgoing frames are KISS-encoded and split into
/// MTU-sized chunks before writing to the RX characteristic.
class BleTncTransport implements KissTncTransport {
  BleTncTransport(
    BluetoothDevice device, {
    BleDeviceAdapter? adapter,
    String serviceUuid = kMobilinkdServiceUuid,
    String txCharUuid = kMobilinkdTxCharUuid,
    String rxCharUuid = kMobilinkdRxCharUuid,
  })  : _adapter = adapter ?? DefaultBleDeviceAdapter(device),
        _serviceUuid = serviceUuid,
        _txCharUuid = txCharUuid,
        _rxCharUuid = rxCharUuid;

  final BleDeviceAdapter _adapter;
  final String _serviceUuid;
  final String _txCharUuid;
  final String _rxCharUuid;

  // Effective MTU for outgoing chunk size (payload bytes, not ATT frame size).
  int _mtu = 20;

  final _kissFramer = KissFramer();
  StreamSubscription<Uint8List>? _framesSub;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connStateSub;

  BluetoothCharacteristic? _txChar;
  BluetoothCharacteristic? _rxChar;

  final _framesController = StreamController<Uint8List>.broadcast();
  final _stateController = StreamController<ConnectionStatus>.broadcast();
  ConnectionStatus _status = ConnectionStatus.disconnected;

  @override
  Stream<Uint8List> get frameStream => _framesController.stream;

  @override
  Stream<ConnectionStatus> get connectionState => _stateController.stream;

  @override
  ConnectionStatus get currentStatus => _status;

  @override
  bool get isConnected => _status == ConnectionStatus.connected;

  @override
  Future<void> connect() async {
    _setStatus(ConnectionStatus.connecting);
    try {
      // 1. Connect to the device.
      await _adapter.connect(
        mtu: 512, // Android: negotiate MTU during connect. No-op on iOS.
        timeout: const Duration(seconds: 15),
      );

      // 2. On iOS the MTU is negotiated by CoreBluetooth automatically.
      //    On other platforms, request explicitly after connect.
      try {
        final negotiated = await _adapter.requestMtu(512);
        // ATT overhead is 3 bytes; subtract to get usable payload bytes.
        _mtu = max(20, negotiated - 3);
        debugPrint('BleTncTransport: MTU negotiated $negotiated, using $_mtu byte chunks');
      } catch (e) {
        debugPrint('BleTncTransport: MTU negotiation failed, using 20-byte fallback: $e');
        _mtu = 20;
      }

      // 3. Discover services (retry up to 3× — Android can fail immediately).
      List<BluetoothService>? services;
      for (int attempt = 1; attempt <= 3; attempt++) {
        try {
          services = await _adapter.discoverServices();
          break;
        } catch (e) {
          debugPrint('BleTncTransport: discoverServices attempt $attempt failed: $e');
          if (attempt == 3) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }

      // 4. Find the TNC GATT service.
      final targetServiceGuid = Guid(_serviceUuid);
      final service = services!.where((s) => s.serviceUuid == targetServiceGuid).firstOrNull;
      if (service == null) {
        throw Exception(
          'BleTncTransport: service $_serviceUuid not found on ${_adapter.platformName}. '
          'Is this a Mobilinkd-compatible TNC?',
        );
      }

      // 5. Find TX (notify) and RX (write) characteristics.
      final txGuid = Guid(_txCharUuid);
      final rxGuid = Guid(_rxCharUuid);
      _txChar = service.characteristics.where((c) => c.characteristicUuid == txGuid).firstOrNull;
      _rxChar = service.characteristics.where((c) => c.characteristicUuid == rxGuid).firstOrNull;

      if (_txChar == null || _rxChar == null) {
        throw Exception(
          'BleTncTransport: TX or RX characteristic not found. '
          'TX found: ${_txChar != null}, RX found: ${_rxChar != null}',
        );
      }

      // 6. Subscribe to TX characteristic notifications.
      await _txChar!.setNotifyValue(true);
      _notifySub = _txChar!.onValueReceived.listen(_onBleChunk);

      // 7. Wire KissFramer output → frameStream.
      _framesSub = _kissFramer.frames.listen(_framesController.add);

      // 8. Monitor for unexpected disconnects.
      _connStateSub = _adapter.connectionState.listen(_onBleConnectionState);

      _setStatus(ConnectionStatus.connected);
    } catch (e) {
      debugPrint('BleTncTransport connect failed: $e');
      _setStatus(ConnectionStatus.error);
      // Best-effort cleanup before rethrowing.
      await _cleanupSubscriptions();
      try {
        await _adapter.disconnect();
      } catch (_) {}
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    if (_status == ConnectionStatus.disconnected) return;
    _setStatus(ConnectionStatus.disconnected);
    await _cleanupSubscriptions();
    try {
      await _txChar?.setNotifyValue(false);
    } catch (_) {}
    _txChar = null;
    _rxChar = null;
    try {
      await _adapter.disconnect();
    } catch (_) {}
    _kissFramer.dispose();
  }

  @override
  Future<void> sendFrame(Uint8List ax25Frame) async {
    final rxChar = _rxChar;
    if (rxChar == null || !isConnected) {
      throw StateError('BleTncTransport: not connected');
    }
    final kissFrame = KissFramer.encode(ax25Frame);
    // Split into MTU-sized chunks and write sequentially with response.
    int offset = 0;
    while (offset < kissFrame.length) {
      final end = min(offset + _mtu, kissFrame.length);
      final chunk = kissFrame.sublist(offset, end);
      await rxChar.write(chunk, withoutResponse: false);
      offset = end;
    }
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  void _onBleChunk(List<int> chunk) {
    _kissFramer.addBytes(chunk);
  }

  void _onBleConnectionState(BluetoothConnectionState state) {
    if (state == BluetoothConnectionState.disconnected &&
        _status == ConnectionStatus.connected) {
      debugPrint('BleTncTransport: unexpected disconnect from ${_adapter.platformName}');
      _status = ConnectionStatus.error;
      _stateController.add(ConnectionStatus.error);
      _cleanupSubscriptions();
    }
  }

  Future<void> _cleanupSubscriptions() async {
    await _notifySub?.cancel();
    _notifySub = null;
    await _connStateSub?.cancel();
    _connStateSub = null;
    await _framesSub?.cancel();
    _framesSub = null;
  }

  void _setStatus(ConnectionStatus status) {
    _status = status;
    _stateController.add(status);
  }
}
