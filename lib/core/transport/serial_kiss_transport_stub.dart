library;

import 'dart:async';
import 'dart:typed_data';

import 'aprs_transport.dart' show ConnectionStatus;
import 'kiss_tnc_transport.dart';
import 'serial_port_adapter.dart';
import 'tnc_config.dart';

/// Stub [SerialKissTransport] for platforms where flutter_libserialport
/// is not available (web, and as a compile-time safety net for mobile).
class SerialKissTransport extends KissTncTransport {
  // ignore: avoid_unused_constructor_parameters
  SerialKissTransport(TncConfig config, {SerialPortAdapter? adapter});

  @override
  Stream<Uint8List> get frameStream =>
      throw UnsupportedError('Serial port not supported on this platform');

  @override
  Stream<ConnectionStatus> get connectionState =>
      throw UnsupportedError('Serial port not supported on this platform');

  @override
  ConnectionStatus get currentStatus => ConnectionStatus.disconnected;

  @override
  bool get isConnected => false;

  @override
  Future<void> connect() =>
      throw UnsupportedError('Serial port not supported on this platform');

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> sendFrame(Uint8List ax25Frame) =>
      throw UnsupportedError('Serial port not supported on this platform');

  static List<String> availablePorts() => const [];
}
