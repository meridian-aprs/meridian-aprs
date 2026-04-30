library;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'aprs_transport.dart' show ConnectionStatus;
import 'ble_constants.dart';
import 'ble_diagnostics.dart';
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

  /// Clears the Android GATT service cache for this device.
  ///
  /// A no-op on iOS/desktop — implementations should swallow any
  /// platform exception so callers never need to handle it.
  Future<void> clearGattCache();

  /// Asks the OS BLE stack to use [priority] for this connection.
  ///
  /// Android only. Implementations on iOS / desktop must silently no-op.
  /// Returns normally on success; throws when the OS rejects the request —
  /// callers should treat that as advisory and continue.
  Future<void> requestConnectionPriority(ConnectionPriority priority);

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
  Future<void> clearGattCache() async {
    try {
      await _device.clearGattCache();
    } catch (_) {
      // Not supported on iOS/desktop — silently ignore.
    }
  }

  @override
  Future<void> requestConnectionPriority(ConnectionPriority priority) async {
    if (!Platform.isAndroid) return;
    await _device.requestConnectionPriority(
      connectionPriorityRequest: priority,
    );
  }

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
    BleDiagnostics.I.log(
      BleEventKind.connectStart,
      'device=${_adapter.platformName} autoConnect=$autoConnect',
    );
    _setStatus(
      autoConnect
          ? ConnectionStatus.waitingForDevice
          : ConnectionStatus.connecting,
    );
    try {
      // 1. Clear the Android GATT cache before connecting.
      //    Stale cached service tables from prior sessions are the most
      //    common cause of GATT status 133 (ANDROID_SPECIFIC_ERROR) on
      //    reconnect. Clearing forces fresh service discovery.
      //    Skipped for autoConnect — the OS manages that session and the
      //    cache is not the source of issues there.
      if (!autoConnect) {
        await _adapter.clearGattCache();
      }

      // 2. Connect to the device.
      //    autoConnect: true — OS manages background scanning; no explicit
      //    timeout needed beyond a ceiling to avoid hanging forever if the
      //    device is turned off permanently.
      await _adapter.connect(
        timeout: autoConnect
            ? const Duration(hours: 1)
            : const Duration(seconds: 15),
        autoConnect: autoConnect,
      );

      // 2a. Subscribe to BLE connection-state events as soon as the OS
      //     considers the link established. The subscription is intentionally
      //     attached BEFORE the rest of setup so an early adverse event
      //     (e.g. a peer-side drop during service discovery) is captured.
      //     It is also intentionally NOT torn down by [_cleanupSubscriptions]
      //     so that a late OS state event still drives the error path.
      _connStateSub ??= _adapter.connectionState.listen(_onBleConnectionState);

      // 2b. Connection-priority request is deliberately skipped.
      //     `BluetoothDevice.requestConnectionPriority(high)` immediately
      //     after `connect()` causes the Mobilinkd TNC4 to drop the link
      //     within the 5.12 s LINK_SUPERVISION_TIMEOUT — the same hardware
      //     quirk that forbids a fresh `requestMtu()` here (see step 3).
      //     The 2026-04-30 drive-test diagnostics showed identical 5.4 s
      //     drop cycles every reconnect with HIGH priority enabled, and a
      //     stable 110 s keepalive cadence with it disabled. Re-introducing
      //     this needs hardware-specific gating; track in a follow-up.
      BleDiagnostics.I.log(
        BleEventKind.connectionPriorityRequested,
        'priority=balanced (skipped: TNC4 drops link if renegotiated)',
      );

      // 3. Read the negotiated MTU.
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

      // 4. Discover services (retry up to 3× — Android BLE stacks sometimes
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
          BleDiagnostics.I.log(
            BleEventKind.serviceDiscoveryRetry,
            'attempt=$attempt error=$e',
          );
          if (attempt == 3) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }

      // 5. Find the TNC GATT service.
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

      // 6. Find TX (notify) and RX (write) characteristics.
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

      // 7. Subscribe to TX characteristic notifications.
      await _txChar!.setNotifyValue(true);
      _notifySub = _txChar!.onValueReceived.listen(_onBleChunk);

      // 8. Wire KissFramer output → frameStream.
      _framesSub = _kissFramer.frames.listen(_framesController.add);

      _setStatus(ConnectionStatus.connected);
      debugPrint(
        'BleTncTransport: connected to ${_adapter.platformName}, starting keepalive timer',
      );
      BleDiagnostics.I.log(
        BleEventKind.connectSuccess,
        'device=${_adapter.platformName} mtu=$_mtu',
      );

      // 10. Start the idle keepalive timer.
      //    Mobilinkd (and most BLE TNCs) will drop the link after a few seconds
      //    of post-connect silence. The keepalive sends a single TXDELAY frame
      //    every 2 s to hold the link open.
      //
      //    NOTE: Do NOT call _sendKissInit() here. Sending the five standard
      //    KISS parameter frames (TXDELAY/PERSIST/SLOTTIME/TXTAIL/FULLDUPLEX)
      //    causes the Mobilinkd TNC4 to reinitialise its modem, which takes its
      //    BLE radio dark for ~5 s — long enough for the supervision timeout
      //    (5.12 s) to expire and drop the connection. The Mobilinkd retains its
      //    own configuration persistently; the host does not need to reprogram
      //    these values on every connect.
      //    DO NOT use command 0x06 (SETHARDWARE) either — that is Mobilinkd's
      //    proprietary config protocol and also causes an immediate disconnect.
      _resetKeepalive();
    } catch (e) {
      debugPrint('BleTncTransport connect failed: $e');
      BleDiagnostics.I.log(
        BleEventKind.connectFailed,
        'device=${_adapter.platformName} error=$e',
      );
      _setStatus(ConnectionStatus.error);
      // Best-effort cleanup before rethrowing — including the connection-state
      // listener, since a failed connect produces no live session for it to
      // observe.
      await _cleanupSubscriptions();
      await _cancelConnStateSub();
      try {
        await _adapter.disconnect();
      } catch (_) {}
      rethrow;
    }
  }

  /// Marks the next [disconnect] call as an internal teardown (e.g. mid-reconnect)
  /// so the diagnostics log records [BleEventKind.disconnectInternal] instead of
  /// [BleEventKind.disconnectUser]. The flag is consumed (cleared) by [disconnect].
  ///
  /// Used by the [BleConnection] layer when rebuilding the transport during a
  /// reconnect attempt — without this, the log was misleadingly attributing
  /// every reconnect cycle's teardown to a user action.
  void markInternalTeardown() {
    _internalTeardown = true;
  }

  bool _internalTeardown = false;

  @override
  Future<void> disconnect() async {
    if (_status == ConnectionStatus.disconnected) return;
    final wasInternal = _internalTeardown;
    _internalTeardown = false;
    BleDiagnostics.I.log(
      wasInternal
          ? BleEventKind.disconnectInternal
          : BleEventKind.disconnectUser,
      'device=${_adapter.platformName}',
    );
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
    _setStatus(ConnectionStatus.disconnected);
    await _cleanupSubscriptions();
    await _cancelConnStateSub();
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
      final chunks = (kissFrame.length + _mtu - 1) ~/ _mtu;
      debugPrint(
        'BleTncTransport: sendFrame ${ax25Frame.length}B → ${kissFrame.length}B KISS in $chunks chunk(s)',
      );
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
    BleDiagnostics.I.log(BleEventKind.bleStateChanged, state.name);
    if (state == BluetoothConnectionState.disconnected &&
        _status == ConnectionStatus.connected) {
      debugPrint(
        'BleTncTransport: unexpected disconnect from ${_adapter.platformName}',
      );
      BleDiagnostics.I.log(
        BleEventKind.disconnectUnexpected,
        'device=${_adapter.platformName}',
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

  /// Cancels per-session subscriptions (notify / framer / keepalive).
  ///
  /// Intentionally does NOT cancel [_connStateSub] — that listener is the
  /// only path by which a late OS-side disconnect can drive the error stream
  /// after this method runs, and it must survive session teardown for that to
  /// work. The listener is cancelled in [disconnect] / [_cancelConnStateSub].
  Future<void> _cleanupSubscriptions() async {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
    await _notifySub?.cancel();
    _notifySub = null;
    await _framesSub?.cancel();
    _framesSub = null;
  }

  Future<void> _cancelConnStateSub() async {
    await _connStateSub?.cancel();
    _connStateSub = null;
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

  // Static so tests can override without making _onKeepalive any wider.
  @visibleForTesting
  static Duration keepaliveRetryDelay = const Duration(milliseconds: 200);

  /// Fires when the link has been idle for [_keepaliveInterval].
  ///
  /// Sends a single KISS TXDELAY frame — harmless to any KISS TNC and
  /// sufficient to reset the Mobilinkd idle timer. Uses write-without-response
  /// to avoid ATT round-trip latency on a fire-and-forget keepalive.
  ///
  /// On write failure the keepalive retries exactly once after a short delay
  /// before declaring the link dead. This absorbs a single transient stall
  /// (Doze transition, brief OS scheduling hiccup) without tripping the full
  /// reconnect cascade. If the retry also fails the link is marked as error.
  Future<void> _onKeepalive() async {
    if (!isConnected) return;
    final rxChar = _rxChar;
    if (rxChar == null) return;
    final payload = Uint8List.fromList([0xC0, 0x01, 30, 0xC0]);
    try {
      await rxChar.write(payload, withoutResponse: true);
      BleDiagnostics.I.log(BleEventKind.keepaliveSent);
      _resetKeepalive();
      return;
    } catch (e) {
      BleDiagnostics.I.log(BleEventKind.keepaliveFailed, 'attempt=1 error=$e');
    }

    // Retry once after a short delay — rebind state in case status changed
    // mid-delay (e.g. user tapped disconnect).
    await Future<void>.delayed(keepaliveRetryDelay);
    if (!isConnected) return;
    final retryRx = _rxChar;
    if (retryRx == null) return;
    try {
      await retryRx.write(payload, withoutResponse: true);
      BleDiagnostics.I.log(BleEventKind.keepaliveRetried, 'recovered=true');
      _resetKeepalive();
      return;
    } catch (e) {
      debugPrint(
        'BleTncTransport: keepalive write failed twice, marking link dropped: $e',
      );
      BleDiagnostics.I.log(BleEventKind.keepaliveFailed, 'attempt=2 error=$e');
      if (_status == ConnectionStatus.connected) {
        BleDiagnostics.I.log(
          BleEventKind.disconnectKeepaliveFailed,
          'device=${_adapter.platformName}',
        );
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
