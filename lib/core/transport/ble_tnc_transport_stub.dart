library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'aprs_transport.dart' show ConnectionStatus;
import 'kiss_tnc_transport.dart';

/// Stub [BleTncTransport] for platforms where BLE is not available (web).
class BleTncTransport extends KissTncTransport {
  // ignore: avoid_unused_constructor_parameters
  BleTncTransport(BluetoothDevice device, {dynamic adapter});

  @override
  Stream<Uint8List> get frameStream =>
      throw UnsupportedError('BLE TNC not supported on this platform');

  @override
  Stream<ConnectionStatus> get connectionState =>
      throw UnsupportedError('BLE TNC not supported on this platform');

  @override
  ConnectionStatus get currentStatus => ConnectionStatus.disconnected;

  @override
  bool get isConnected => false;

  @override
  Future<void> connect() =>
      throw UnsupportedError('BLE TNC not supported on this platform');

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> sendFrame(Uint8List ax25Frame) =>
      throw UnsupportedError('BLE TNC not supported on this platform');
}
