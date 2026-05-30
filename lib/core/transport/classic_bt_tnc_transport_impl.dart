library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import 'aprs_transport.dart' show ConnectionStatus;
import 'classic_bt_spp_channel.dart';
import 'kiss_framer.dart';
import 'kiss_tnc_transport.dart';

/// Classic Bluetooth SPP (RFCOMM) KISS TNC transport (ADR-069).
///
/// The serial twin of [SerialKissTransport]: a raw bidirectional byte stream,
/// not a GATT model. Implements [KissTncTransport], emitting raw AX.25 frame
/// payloads on [frameStream]. Internally:
///   native RX bytes → [KissFramer] → AX.25 bytes on [frameStream]
///   [sendFrame] → [KissFramer.encode] → native `write`
///
/// Android only in v0.21. Use the conditional-import shim at
/// `classic_bt_tnc_transport.dart` rather than importing this file directly.
///
/// The native [EventChannel] is single-sink: only one `receiveBroadcastStream`
/// listener can be active at a time. To avoid sink races across reconnect
/// churn, the owning [ClassicBtConnection] creates **one** long-lived
/// [ClassicBtSppChannel] and injects it here; per-connect transports merely
/// subscribe to the channel's Dart-side broadcast streams. The transport
/// therefore never disposes the channel — it only closes the active socket via
/// [ClassicBtSppChannel.disconnect].
class ClassicBtTncTransport extends KissTncTransport {
  ClassicBtTncTransport(this._address, {ClassicBtSppChannel? channel})
    : _channel = channel ?? ClassicBtSppChannel();

  final String _address;
  final ClassicBtSppChannel _channel;

  final _kissFramer = KissFramer();
  StreamSubscription<Uint8List>? _rxSub;
  StreamSubscription<ClassicBtStateEvent>? _stateSub;
  StreamSubscription<Uint8List>? _frameSub;

  final _framesController = StreamController<Uint8List>.broadcast();
  final _stateController = StreamController<ConnectionStatus>.broadcast();
  ConnectionStatus _status = ConnectionStatus.disconnected;

  /// Last human-readable failure reason reported by the native bridge.
  String? get lastErrorMessage => _lastErrorMessage;
  String? _lastErrorMessage;

  /// Guards against concurrent or re-entrant disconnect calls.
  bool _disconnecting = false;

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

    // Subscribe KISS frames → frameStream.
    _frameSub = _kissFramer.frames.listen(_onAx25Frame);

    // Subscribe native RX bytes → KISS framer. Accessing the channel streams
    // lazily starts the single native EventChannel subscription (once for the
    // channel's lifetime).
    _rxSub = _channel.rxBytes.listen(
      (bytes) => _kissFramer.addBytes(bytes),
      onError: (Object e) {
        debugPrint('ClassicBtTncTransport rx error: $e');
        _lastErrorMessage = e.toString();
        _setStatus(ConnectionStatus.error);
        Future.microtask(_handleDisconnect);
      },
    );

    // Subscribe native link-state transitions. The actual connected/error
    // outcome of the RFCOMM connect arrives here, not from [connect]'s future
    // (which resolves as soon as the request is dispatched).
    _stateSub = _channel.states.listen(_onStateEvent);

    try {
      await _channel.connect(_address);
    } catch (e) {
      debugPrint('ClassicBtTncTransport connect dispatch failed: $e');
      _lastErrorMessage = e.toString();
      _setStatus(ConnectionStatus.error);
      Future.microtask(_handleDisconnect);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    await _handleDisconnect();
  }

  @override
  Future<void> sendFrame(Uint8List ax25Frame) async {
    try {
      await _channel.write(KissFramer.encode(ax25Frame));
    } catch (e) {
      debugPrint('ClassicBtTncTransport: sendFrame error — $e');
      _lastErrorMessage = e.toString();
      Future.microtask(_handleDisconnect);
      rethrow;
    }
  }

  void _onStateEvent(ClassicBtStateEvent event) {
    switch (event.state) {
      case ClassicBtLinkState.connecting:
        _setStatus(ConnectionStatus.connecting);
      case ClassicBtLinkState.connected:
        _setStatus(ConnectionStatus.connected);
      case ClassicBtLinkState.disconnected:
        if (!_disconnecting) Future.microtask(_handleDisconnect);
      case ClassicBtLinkState.error:
        _lastErrorMessage = event.message;
        _setStatus(ConnectionStatus.error);
        if (!_disconnecting) Future.microtask(_handleDisconnect);
    }
  }

  /// Idempotent teardown. Safe to call from stream callbacks, [disconnect], or
  /// error handlers. Closes the active socket but never disposes the shared
  /// [ClassicBtSppChannel].
  Future<void> _handleDisconnect() async {
    if (_disconnecting) return;
    _disconnecting = true;

    await _rxSub?.cancel();
    _rxSub = null;
    await _stateSub?.cancel();
    _stateSub = null;
    await _frameSub?.cancel();
    _frameSub = null;
    _kissFramer.dispose();

    try {
      await _channel.disconnect();
    } catch (e) {
      // The socket may already be gone after a physical disconnect — swallow.
      debugPrint('ClassicBtTncTransport channel.disconnect() error: $e');
    }

    if (_status != ConnectionStatus.error) {
      _setStatus(ConnectionStatus.disconnected);
    }
    _disconnecting = false;
  }

  /// All already-bonded Classic BT devices (OS-paired). No in-app discovery —
  /// pairing is owned by Android Bluetooth settings.
  ///
  /// Uses a transient channel: [ClassicBtSppChannel.listPaired] is a plain
  /// method call that never touches the single-sink event stream, so no live
  /// session is disturbed.
  static Future<List<ClassicBtPairedDevice>> pairedDevices() =>
      ClassicBtSppChannel().listPaired();

  void _onAx25Frame(Uint8List frameBytes) {
    if (!_framesController.isClosed) _framesController.add(frameBytes);
  }

  void _setStatus(ConnectionStatus status) {
    _status = status;
    if (!_stateController.isClosed) _stateController.add(status);
  }
}
