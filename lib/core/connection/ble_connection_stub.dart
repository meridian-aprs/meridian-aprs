library;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../transport/kiss_tnc_transport.dart';
import '../util/clock.dart';
import 'meridian_connection.dart';

/// Stub [BleConnection] for platforms where BLE is not supported (web, desktop).
class BleConnection extends MeridianConnection {
  BleConnection({Clock clock = DateTime.now});

  @visibleForTesting
  KissTncTransport Function(dynamic)? transportFactory;

  @override
  String get id => 'ble_tnc';

  @override
  String get displayName => 'BLE TNC';

  @override
  ConnectionType get type => ConnectionType.bleTnc;

  @override
  bool get isAvailable => false;

  @override
  ConnectionStatus get status => ConnectionStatus.disconnected;

  @override
  Stream<ConnectionStatus> get connectionState =>
      throw UnsupportedError('BLE not supported on this platform');

  @override
  bool get isConnected => false;

  @override
  bool get beaconingEnabled => false;

  @override
  Future<void> setBeaconingEnabled(bool enabled) =>
      throw UnsupportedError('BLE not supported on this platform');

  @override
  Stream<String> get lines =>
      throw UnsupportedError('BLE not supported on this platform');

  @override
  Future<void> sendLine(String aprsLine, {List<String>? digipeaterPath}) =>
      throw UnsupportedError('BLE not supported on this platform');

  @override
  Future<void> connect() =>
      throw UnsupportedError('BLE not supported on this platform');

  Future<void> connectToDevice(dynamic device, {dynamic family}) =>
      throw UnsupportedError('BLE not supported on this platform');

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {
    super.dispose();
  }

  @override
  Future<void> loadPersistedSettings() async {}
}
