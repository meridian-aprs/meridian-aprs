import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Link-state transitions reported by the native Classic BT bridge.
enum ClassicBtLinkState { connecting, connected, disconnected, error }

/// A bonded (already-paired) Classic Bluetooth device. Pairing is owned by the
/// OS; Meridian only lists and connects to devices the user paired in system
/// Bluetooth settings.
typedef ClassicBtPairedDevice = ({String address, String name});

/// A link-state event with an optional human-readable failure reason.
typedef ClassicBtStateEvent = ({ClassicBtLinkState state, String? message});

/// Thin Dart wrapper over the native Classic Bluetooth SPP (RFCOMM) bridge
/// (ADR-069). Mirrors a serial port: a raw bidirectional byte stream. KISS
/// framing, AX.25, and reconnect live above this — see [ClassicBtTncTransport].
///
/// One active socket at a time. RX bytes and link-state transitions arrive on a
/// single native [EventChannel] and are demultiplexed into [rxBytes] / [states].
/// Instantiate only where the platform supports it (Android in v0.21); the
/// methods otherwise reject with a [PlatformException].
class ClassicBtSppChannel {
  ClassicBtSppChannel({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  }) : _method = methodChannel ?? const MethodChannel(_methodName),
       _event = eventChannel ?? const EventChannel(_eventName);

  static const _methodName = 'meridian/classic_bt';
  static const _eventName = 'meridian/classic_bt/rx';

  final MethodChannel _method;
  final EventChannel _event;

  final _rxController = StreamController<Uint8List>.broadcast();
  final _stateController = StreamController<ClassicBtStateEvent>.broadcast();
  StreamSubscription<dynamic>? _eventSub;
  bool _listening = false;

  /// Raw bytes received from the device. Feed into `KissFramer.addBytes`.
  Stream<Uint8List> get rxBytes {
    _ensureListening();
    return _rxController.stream;
  }

  /// Link-state transitions (connecting → connected, or → error/disconnected).
  Stream<ClassicBtStateEvent> get states {
    _ensureListening();
    return _stateController.stream;
  }

  /// Whether the device has a usable Bluetooth adapter.
  Future<bool> isSupported() async =>
      await _method.invokeMethod<bool>('isSupported') ?? false;

  /// All already-bonded Classic BT devices (OS-paired). No in-app discovery.
  Future<List<ClassicBtPairedDevice>> listPaired() async {
    final raw =
        await _method.invokeListMethod<dynamic>('listPaired') ?? const [];
    return raw
        .map<ClassicBtPairedDevice>((e) {
          final m = (e as Map).cast<dynamic, dynamic>();
          final address = m['address'] as String? ?? '';
          return (address: address, name: m['name'] as String? ?? address);
        })
        .toList(growable: false);
  }

  /// Open an RFCOMM socket to [address]. Returns once the request is dispatched;
  /// the actual connected/error outcome arrives on [states].
  Future<void> connect(String address) =>
      _method.invokeMethod<void>('connect', {'address': address});

  /// Close the active socket, if any.
  Future<void> disconnect() => _method.invokeMethod<void>('disconnect');

  /// Write raw bytes to the device (KISS-encoded frame).
  Future<void> write(Uint8List bytes) =>
      _method.invokeMethod<void>('write', {'bytes': bytes});

  void _ensureListening() {
    if (_listening) return;
    _listening = true;
    _eventSub = _event.receiveBroadcastStream().listen(
      _onEvent,
      onError: (Object e) {
        if (!_stateController.isClosed) {
          _stateController.add((
            state: ClassicBtLinkState.error,
            message: e.toString(),
          ));
        }
      },
    );
  }

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    switch (event['event']) {
      case 'data':
        final bytes = event['bytes'];
        if (bytes is Uint8List && !_rxController.isClosed) {
          _rxController.add(bytes);
        }
      case 'state':
        final state = switch (event['state']) {
          'connecting' => ClassicBtLinkState.connecting,
          'connected' => ClassicBtLinkState.connected,
          'disconnected' => ClassicBtLinkState.disconnected,
          _ => ClassicBtLinkState.error,
        };
        if (!_stateController.isClosed) {
          _stateController.add((
            state: state,
            message: event['message'] as String?,
          ));
        }
      default:
        debugPrint('ClassicBtSppChannel: unknown event $event');
    }
  }

  Future<void> dispose() async {
    await _eventSub?.cancel();
    _eventSub = null;
    await _rxController.close();
    await _stateController.close();
  }
}
