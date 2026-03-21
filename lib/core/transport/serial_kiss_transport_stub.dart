library;

import 'dart:async';

import 'aprs_transport.dart';
import 'serial_port_adapter.dart';
import 'tnc_config.dart';

/// Stub [SerialKissTransport] for platforms where flutter_libserialport
/// is not available (web, and as a compile-time safety net for mobile).
class SerialKissTransport implements AprsTransport {
  // ignore: avoid_unused_constructor_parameters
  SerialKissTransport(TncConfig config, {SerialPortAdapter? adapter});

  @override
  Stream<String> get lines =>
      throw UnsupportedError('Serial port not supported on this platform');

  @override
  Stream<ConnectionStatus> get connectionState =>
      throw UnsupportedError('Serial port not supported on this platform');

  @override
  ConnectionStatus get currentStatus => ConnectionStatus.disconnected;

  @override
  Future<void> connect() =>
      throw UnsupportedError('Serial port not supported on this platform');

  @override
  Future<void> disconnect() async {}

  @override
  void sendLine(String line) {}

  static List<String> availablePorts() => const [];
}
