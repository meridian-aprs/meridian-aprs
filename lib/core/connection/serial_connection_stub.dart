library;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../transport/kiss_tnc_transport.dart';
import '../transport/tnc_config.dart';
import 'meridian_connection.dart';

/// Stub [SerialConnection] for platforms where serial is not supported (web).
class SerialConnection extends MeridianConnection {
  SerialConnection();

  @visibleForTesting
  KissTncTransport Function(TncConfig)? transportFactory;

  @override
  String get id => 'serial_tnc';

  @override
  String get displayName => 'USB TNC';

  @override
  ConnectionType get type => ConnectionType.serialTnc;

  @override
  bool get isAvailable => false;

  @override
  ConnectionStatus get status => ConnectionStatus.disconnected;

  @override
  Stream<ConnectionStatus> get connectionState =>
      throw UnsupportedError('Serial not supported on this platform');

  @override
  bool get isConnected => false;

  @override
  bool get beaconingEnabled => false;

  @override
  Future<void> setBeaconingEnabled(bool enabled) =>
      throw UnsupportedError('Serial not supported on this platform');

  @override
  Stream<String> get lines =>
      throw UnsupportedError('Serial not supported on this platform');

  @override
  Future<void> sendLine(String aprsLine, {List<String>? digipeaterPath}) =>
      throw UnsupportedError('Serial not supported on this platform');

  @override
  Future<void> connect() =>
      throw UnsupportedError('Serial not supported on this platform');

  Future<void> connectWithConfig(TncConfig config) =>
      throw UnsupportedError('Serial not supported on this platform');

  TncConfig? get activeConfig => null;
  String? get lastErrorMessage => null;
  List<String> availablePorts() => const [];

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {
    super.dispose();
  }

  @override
  Future<void> loadPersistedSettings() async {}
}
