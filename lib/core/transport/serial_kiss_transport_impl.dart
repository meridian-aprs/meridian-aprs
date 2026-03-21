library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_libserialport/flutter_libserialport.dart';

import '../packet/aprs_parser.dart';
import 'aprs_transport.dart';
import 'kiss_framer.dart';
import 'serial_port_adapter.dart';
import 'serial_port_adapter_impl.dart';
import 'tnc_config.dart';

/// USB serial KISS TNC transport.
///
/// Implements [AprsTransport] so that [StationService] can consume APRS
/// packets from a hardware TNC over USB serial without any changes to the
/// service layer. Internally performs:
///   raw serial bytes → [KissFramer] → [AprsParser.parseFrame] → APRS line
///
/// Desktop only (Linux, macOS, Windows). Use the conditional import shim
/// at `serial_kiss_transport.dart` rather than importing this file directly.
///
/// Pass a custom [SerialPortAdapter] to inject a fake in tests.
class SerialKissTransport implements AprsTransport {
  SerialKissTransport(this._config, {SerialPortAdapter? adapter})
    : _adapter = adapter ?? DefaultSerialPortAdapter(_config.port);

  final TncConfig _config;
  final SerialPortAdapter _adapter;

  StreamSubscription<Uint8List>? _readerSub;

  final _kissFramer = KissFramer();
  StreamSubscription<Uint8List>? _frameSub;
  final _aprsParser = AprsParser();

  final _linesController = StreamController<String>.broadcast();
  final _stateController = StreamController<ConnectionStatus>.broadcast();
  ConnectionStatus _status = ConnectionStatus.disconnected;

  @override
  Stream<String> get lines => _linesController.stream;

  @override
  Stream<ConnectionStatus> get connectionState => _stateController.stream;

  @override
  ConnectionStatus get currentStatus => _status;

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

      // Subscribe KISS frames → APRS line emission.
      _frameSub = _kissFramer.frames.listen(_onFrame);

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

  /// No-op in v0.3. Transmit path is v0.5 beaconing.
  @override
  void sendLine(String line) {}

  /// Returns the list of available serial port names on the host system.
  static List<String> availablePorts() => SerialPort.availablePorts;

  void _onFrame(Uint8List frameBytes) {
    final packet = _aprsParser.parseFrame(frameBytes);
    // packet.rawLine is the reconstructed APRS-IS–format line.
    // An empty rawLine means AX.25 decode failed; StationService silently
    // ignores empty lines, so we can emit unconditionally.
    _linesController.add(packet.rawLine);
  }

  void _setStatus(ConnectionStatus status) {
    _status = status;
    _stateController.add(status);
  }
}
