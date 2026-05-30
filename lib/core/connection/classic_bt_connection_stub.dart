library;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../transport/classic_bt_spp_channel.dart';
import '../transport/kiss_tnc_transport.dart';
import '../util/clock.dart';
import 'meridian_connection.dart';

/// Stub [ClassicBtConnection] for platforms without Classic BT SPP (web).
class ClassicBtConnection extends MeridianConnection {
  ClassicBtConnection({
    Clock clock = DateTime.now,
    ClassicBtSppChannel? channel,
  });

  @visibleForTesting
  KissTncTransport Function(String address)? transportFactory;

  @override
  String get id => 'classic_bt_tnc';

  @override
  String get displayName => 'Classic BT';

  @override
  ConnectionType get type => ConnectionType.classicBtTnc;

  @override
  bool get isAvailable => false;

  @override
  ConnectionStatus get status => ConnectionStatus.disconnected;

  @override
  Stream<ConnectionStatus> get connectionState =>
      throw UnsupportedError('Classic BT not supported on this platform');

  @override
  bool get isConnected => false;

  @override
  bool get beaconingEnabled => false;

  @override
  Future<void> setBeaconingEnabled(bool enabled) =>
      throw UnsupportedError('Classic BT not supported on this platform');

  @override
  Stream<String> get lines =>
      throw UnsupportedError('Classic BT not supported on this platform');

  @override
  Future<void> sendLine(String aprsLine, {List<String>? digipeaterPath}) =>
      throw UnsupportedError('Classic BT not supported on this platform');

  @override
  Future<void> connect() =>
      throw UnsupportedError('Classic BT not supported on this platform');

  Future<void> connectToDevice(String address, {String? name}) =>
      throw UnsupportedError('Classic BT not supported on this platform');

  String? get deviceAddress => null;
  String? get deviceName => null;
  String? get lastErrorMessage => null;
  Future<List<ClassicBtPairedDevice>> pairedDevices() async => const [];

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {
    super.dispose();
  }

  @override
  Future<void> loadPersistedSettings() async {}
}
