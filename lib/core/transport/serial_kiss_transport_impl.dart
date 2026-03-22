library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'aprs_transport.dart' show ConnectionStatus;
import 'kiss_framer.dart';
import 'kiss_tnc_transport.dart';
import 'serial_port_adapter.dart';
import 'serial_port_adapter_impl.dart';
import 'tnc_config.dart';

/// USB serial KISS TNC transport.
///
/// Implements [KissTncTransport], emitting raw AX.25 frame payloads on
/// [frameStream]. APRS parsing is the responsibility of the caller (service
/// layer). Internally performs:
///   raw serial bytes → [KissFramer] → AX.25 bytes on [frameStream]
///
/// Desktop only (Linux, macOS, Windows). Use the conditional import shim
/// at `serial_kiss_transport.dart` rather than importing this file directly.
///
/// Pass a custom [SerialPortAdapter] to inject a fake in tests.
class SerialKissTransport implements KissTncTransport {
  SerialKissTransport(this._config, {SerialPortAdapter? adapter})
    : _adapter = adapter ?? DefaultSerialPortAdapter(_config.port);

  final TncConfig _config;
  final SerialPortAdapter _adapter;

  StreamSubscription<Uint8List>? _readerSub;

  final _kissFramer = KissFramer();
  StreamSubscription<Uint8List>? _frameSub;

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
      if (!_adapter.open()) {
        throw Exception('Failed to open port ${_config.port}');
      }

      _adapter.configure(
        baudRate: _config.baudRate,
        dataBits: _config.dataBits,
        stopBits: _config.stopBits,
        parity: _config.parity,
        hardwareFlowControl: _config.hardwareFlowControl,
      );

      // Subscribe KISS frames → frameStream.
      _frameSub = _kissFramer.frames.listen(_onAx25Frame);

      // Subscribe serial reader → KISS framer.
      _readerSub = _adapter.byteStream.listen(
        (bytes) => _kissFramer.addBytes(bytes),
        onError: (Object e) {
          debugPrint('SerialKissTransport read error: $e');
          _setStatus(ConnectionStatus.error);
        },
        onDone: () {
          debugPrint('SerialKissTransport: port closed');
          _setStatus(ConnectionStatus.disconnected);
        },
      );

      _setStatus(ConnectionStatus.connected);
    } catch (e) {
      debugPrint('SerialKissTransport connect failed: $e');
      _setStatus(ConnectionStatus.error);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    await _readerSub?.cancel();
    _readerSub = null;
    await _frameSub?.cancel();
    _frameSub = null;
    _kissFramer.dispose();
    _adapter.close();
    _setStatus(ConnectionStatus.disconnected);
  }

  @override
  Future<void> sendFrame(Uint8List ax25Frame) async {
    _adapter.write(KissFramer.encode(ax25Frame));
  }

  /// Returns the list of available serial port names on the host system.
  static List<String> availablePorts() => SerialPort.availablePorts;

  void _onAx25Frame(Uint8List frameBytes) {
    _framesController.add(frameBytes);
  }

  void _setStatus(ConnectionStatus status) {
    _status = status;
    _stateController.add(status);
  }
}
