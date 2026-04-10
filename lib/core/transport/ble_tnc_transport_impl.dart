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
  Future<void> connect({Duration timeout, bool autoConnect});
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
  Future<void> connect({
    Duration timeout = const Duration(seconds: 15),
    bool autoConnect = false,
  }) => _device.connect(timeout: timeout, autoConnect: autoConnect);

  @override
  Future<void> disconnect() => _device.disconnect();

  @override
  Future<int> requestMtu(int desired) => _device.requestMtu(desired);

  @override
  int get mtu => _device.mtuNow;

  @override
  Future<List<BluetoothService>> discoverServices() =>
      _device.discoverServices();

  @override
  Stream<BluetoothConnectionState> get connectionState =>
      _device.connectionState;

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
///   scan → connect → discoverServices
///   → subscribe to TX characteristic → ready
///
/// Incoming BLE chunks are reassembled into complete KISS frames by the
/// existing [KissFramer]. Outgoing frames are KISS-encoded and split into
/// MTU-sized chunks before writing to the RX characteristic.
class BleTncTransport extends KissTncTransport {
  BleTncTransport(
    BluetoothDevice device, {
    BleDeviceAdapter? adapter,
    String serviceUuid = kMobilinkdServiceUuid,
    String txCharUuid = kMobilinkdTxCharUuid,
    String rxCharUuid = kMobilinkdRxCharUuid,
  }) : _adapter = adapter ?? DefaultBleDeviceAdapter(device),
       _serviceUuid = serviceUuid,
       _txCharUuid = txCharUuid,
       _rxCharUuid = rxCharUuid;

  final BleDeviceAdapter _adapter;
  final String _serviceUuid;
  final String _txCharUuid;
  final String _rxCharUuid;

  // Effective MTU for outgoing chunk size (payload bytes, not ATT frame size).
  int _mtu = 20;

  // Keepalive: reset on every write; fires if the link is idle for too long.
  // Mobilinkd (and most BLE TNCs) drop the connection after ~5 s of silence.
  // 2 s gives comfortable headroom below the 5.12 s supervision timeout.
  static const _keepaliveInterval = Duration(seconds: 2);
  Timer? _keepaliveTimer;

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

  /// Connect using OS background scanning (autoConnect mode).
  ///
  /// Emits [ConnectionStatus.waitingForDevice] while the OS scans, then
  /// transitions to [ConnectionStatus.connected] once the device is found.
  /// The wait is up to one hour; calling [disconnect] cancels it.
  @override
  Future<void> connectBackground() => _connect(autoConnect: true);

  @override
  Future<void> connect() => _connect(autoConnect: false);

  Future<void> _connect({required bool autoConnect}) async {
    _setStatus(
      autoConnect
          ? ConnectionStatus.waitingForDevice
          : ConnectionStatus.connecting,
    );
    try {
      // 1. Connect to the device.
      //    autoConnect: true — OS manages background scanning; no explicit
      //    timeout needed beyond a ceiling to avoid hanging forever if the
      //    device is turned off permanently.
      await _adapter.connect(
        timeout: autoConnect
            ? const Duration(hours: 1)
            : const Duration(seconds: 15),
        autoConnect: autoConnect,
      );

      // 2. Read the negotiated MTU.
      //    flutter_blue_plus on Android auto-requests MTU 512 inside
      //    connect(); issuing a second requestMtu() immediately after causes
      //    Mobilinkd (and some other TNCs) to drop the link with
      //    LINK_SUPERVISION_TIMEOUT. On iOS the OS manages MTU negotiation
      //    and explicit requests are unnecessary. _adapter.mtu reflects the
      //    negotiated value once connect() resolves.
      //    ATT overhead is 3 bytes; subtract to get usable payload bytes.
      final negotiated = _adapter.mtu;
      _mtu = max(20, negotiated - 3);
      debugPrint('BleTncTransport: MTU $negotiated, using $_mtu byte chunks');

      // 3. Discover services (retry up to 3× — Android BLE stacks sometimes
      //    need a moment after connect() before the GATT cache is ready).
      List<BluetoothService>? services;
      for (int attempt = 1; attempt <= 3; attempt++) {
        try {
          if (attempt == 1) {
            // Brief settle time before first attempt — Android BLE timing.
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
          services = await _adapter.discoverServices();
          break;
        } catch (e) {
          debugPrint(
            'BleTncTransport: discoverServices attempt $attempt failed: $e',
          );
          if (attempt == 3) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }

      // 4. Find the TNC GATT service.
      final targetServiceGuid = Guid(_serviceUuid);
      final service = services!
          .where((s) => s.serviceUuid == targetServiceGuid)
          .firstOrNull;
      if (service == null) {
        throw Exception(
          'BleTncTransport: service $_serviceUuid not found on ${_adapter.platformName}. '
          'Is this a Mobilinkd-compatible TNC?',
        );
      }

      // 5. Find TX (notify) and RX (write) characteristics.
      final txGuid = Guid(_txCharUuid);
      final rxGuid = Guid(_rxCharUuid);
      _txChar = service.characteristics
          .where((c) => c.characteristicUuid == txGuid)
          .firstOrNull;
      _rxChar = service.characteristics
          .where((c) => c.characteristicUuid == rxGuid)
          .firstOrNull;

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

      // 9. Send the standard KISS parameter initialisation sequence and start
      //    the idle keepalive timer.
      //    Mobilinkd (and most BLE TNCs) will drop the link after a few seconds
      //    of post-connect silence. Sending the five standard KISS commands
      //    immediately resets the TNC idle timer. All five frames are packed
      //    into one BLE write (20 bytes) to minimise round-trips.
      //    DO NOT use command 0x06 (SETHARDWARE) — that is Mobilinkd's
      //    proprietary config protocol and causes an immediate disconnect.
      await _sendKissInit();
      _resetKeepalive();
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
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
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
    _keepaliveTimer?.cancel();
    try {
      final kissFrame = KissFramer.encode(ax25Frame);
      // Split into MTU-sized chunks and write sequentially with response.
      int offset = 0;
      while (offset < kissFrame.length) {
        final end = min(offset + _mtu, kissFrame.length);
        final chunk = kissFrame.sublist(offset, end);
        await rxChar.write(chunk, withoutResponse: false);
        offset = end;
      }
    } finally {
      // Always reschedule the keepalive — even on write failure — so the
      // timer isn't left permanently cancelled if the caller catches the error
      // and keeps the connection open.
      _resetKeepalive();
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
      debugPrint(
        'BleTncTransport: unexpected disconnect from ${_adapter.platformName}',
      );
      // _status is set synchronously before the unawaited cleanup, so a
      // second delivery of this event cannot re-enter (guard is already false).
      // The keepalive timer is also cancelled synchronously on the first line
      // of _cleanupSubscriptions, so no keepalive can fire mid-cleanup.
      _status = ConnectionStatus.error;
      _stateController.add(ConnectionStatus.error);
      _cleanupSubscriptions(); // unawaited — safe, see above
    }
  }

  Future<void> _cleanupSubscriptions() async {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
    await _notifySub?.cancel();
    _notifySub = null;
    await _connStateSub?.cancel();
    _connStateSub = null;
    await _framesSub?.cancel();
    _framesSub = null;
  }

  /// Sends the five standard KISS parameter frames in a single BLE write.
  ///
  /// Frame layout: FEND CMD VALUE FEND (4 bytes each, 20 bytes total).
  ///   0x01 TXDELAY   – 30 × 10 ms = 300 ms
  ///   0x02 PERSIST   – 63  (standard CSMA)
  ///   0x03 SLOTTIME  – 10 × 10 ms = 100 ms
  ///   0x04 TXTAIL    – 0 ms
  ///   0x05 FULLDUPLEX – off (CSMA mode)
  Future<void> _sendKissInit() async {
    try {
      await _rxChar?.write(
        Uint8List.fromList([
          0xC0, 0x01, 30, 0xC0, // TXDELAY  300 ms
          0xC0, 0x02, 63, 0xC0, // PERSIST
          0xC0, 0x03, 10, 0xC0, // SLOTTIME 100 ms
          0xC0, 0x04, 0, 0xC0, // TXTAIL     0 ms
          0xC0, 0x05, 0, 0xC0, // FULLDUPLEX off
        ]),
        withoutResponse: false,
      );
    } catch (_) {
      // Best-effort — TNC will still operate without the init sequence.
    }
  }

  /// Cancels any pending keepalive and schedules a new one.
  ///
  /// Call after every outbound write so the timer only fires during genuine
  /// silence. When real APRS traffic is flowing the timer is continuously
  /// reset and never actually fires.
  void _resetKeepalive() {
    _keepaliveTimer?.cancel();
    if (!isConnected) return;
    _keepaliveTimer = Timer(_keepaliveInterval, _onKeepalive);
  }

  /// Fires when the link has been idle for [_keepaliveInterval].
  ///
  /// Sends a single KISS TXDELAY frame — harmless to any KISS TNC and
  /// sufficient to reset the Mobilinkd idle timer. Uses write-without-response
  /// to avoid ATT round-trip latency on a fire-and-forget keepalive.
  /// A write failure is treated as a link-dropped signal rather than
  /// silently rescheduling, ensuring the UI reflects the real state promptly.
  Future<void> _onKeepalive() async {
    if (!isConnected) return;
    try {
      await _rxChar?.write(
        Uint8List.fromList([0xC0, 0x01, 30, 0xC0]),
        withoutResponse: true,
      );
      _resetKeepalive();
    } catch (e) {
      // Write failure means the link is gone. Mark as error immediately
      // rather than silently rescheduling — don't wait for the BLE stack
      // to eventually fire an onConnectionStateChange event.
      debugPrint(
        'BleTncTransport: keepalive write failed, marking link dropped: $e',
      );
      if (_status == ConnectionStatus.connected) {
        _status = ConnectionStatus.error;
        _stateController.add(ConnectionStatus.error);
        await _cleanupSubscriptions();
      }
    }
  }

  void _setStatus(ConnectionStatus status) {
    _status = status;
    _stateController.add(status);
  }
}
