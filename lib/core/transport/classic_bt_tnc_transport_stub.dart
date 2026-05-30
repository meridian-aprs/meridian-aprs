library;

import 'dart:async';
import 'dart:typed_data';

import 'aprs_transport.dart' show ConnectionStatus;
import 'classic_bt_spp_channel.dart';
import 'kiss_tnc_transport.dart';

/// Stub [ClassicBtTncTransport] for platforms without Classic BT SPP (web).
class ClassicBtTncTransport extends KissTncTransport {
  // ignore: avoid_unused_constructor_parameters
  ClassicBtTncTransport(String address, {ClassicBtSppChannel? channel});

  static const _unsupported =
      'Classic Bluetooth not supported on this platform';

  String? get lastErrorMessage => null;

  @override
  Stream<Uint8List> get frameStream => throw UnsupportedError(_unsupported);

  @override
  Stream<ConnectionStatus> get connectionState =>
      throw UnsupportedError(_unsupported);

  @override
  ConnectionStatus get currentStatus => ConnectionStatus.disconnected;

  @override
  bool get isConnected => false;

  @override
  Future<void> connect() => throw UnsupportedError(_unsupported);

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> sendFrame(Uint8List ax25Frame) =>
      throw UnsupportedError(_unsupported);

  static Future<List<ClassicBtPairedDevice>> pairedDevices() async => const [];
}
