/// Tests that [TxService] routes outgoing TX correctly when licensed.
///
/// `sendLine` follows the unconditional Serial > BLE > APRS-IS hierarchy
/// (ADR-029) with an optional `forceVia` per-message override. `sendBeacon`
/// fans out to every connected connection where `beaconingEnabled` is true.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meridian_aprs/core/connection/connection_registry.dart';
import 'package:meridian_aprs/services/station_settings_service.dart';
import 'package:meridian_aprs/services/tx_service.dart';

import '../helpers/fake_meridian_connection.dart';
import '../helpers/fake_secure_credential_store.dart';

void main() {
  late SharedPreferences prefs;
  late StationSettingsService settings;
  late ConnectionRegistry registry;
  late TxService tx;

  Future<void> baseSetUp() async {
    SharedPreferences.setMockInitialValues({
      'user_callsign': 'W1AW',
      'user_ssid': 9,
      'user_is_licensed': true,
    });
    prefs = await SharedPreferences.getInstance();
    settings = StationSettingsService(
      prefs,
      store: FakeSecureCredentialStore(),
    );
    registry = ConnectionRegistry();
  }

  FakeMeridianConnection makeConn({
    required String id,
    required ConnectionType type,
    bool connected = true,
  }) {
    final conn = FakeMeridianConnection(id: id, displayName: id, type: type);
    registry.register(conn);
    if (connected) conn.setStatus(ConnectionStatus.connected);
    return conn;
  }

  group('TxService — sendLine routing hierarchy (licensed)', () {
    setUp(() async {
      await baseSetUp();
      tx = TxService(registry, settings);
    });

    tearDown(() async {
      tx.dispose();
      for (final c in registry.all) {
        await c.dispose();
      }
    });

    test('no connections → silent noop', () async {
      // Empty registry: nothing to send to, nothing throws.
      await tx.sendLine('TEST');
      expect(registry.all, isEmpty);
    });

    test('APRS-IS only → routes to APRS-IS', () async {
      final aprsIs = makeConn(id: 'aprs_is', type: ConnectionType.aprsIs);
      await tx.sendLine('LINE');
      expect(aprsIs.lastSentLine, 'LINE');
    });

    test('Serial + APRS-IS → Serial wins', () async {
      final serial = makeConn(id: 'serial', type: ConnectionType.serialTnc);
      final aprsIs = makeConn(id: 'aprs_is', type: ConnectionType.aprsIs);
      await tx.sendLine('LINE');
      expect(serial.lastSentLine, 'LINE');
      expect(aprsIs.lastSentLine, isNull);
    });

    test('BLE + APRS-IS → BLE wins', () async {
      final ble = makeConn(id: 'ble', type: ConnectionType.bleTnc);
      final aprsIs = makeConn(id: 'aprs_is', type: ConnectionType.aprsIs);
      await tx.sendLine('LINE');
      expect(ble.lastSentLine, 'LINE');
      expect(aprsIs.lastSentLine, isNull);
    });

    test('Serial + BLE + APRS-IS all connected → Serial wins', () async {
      final serial = makeConn(id: 'serial', type: ConnectionType.serialTnc);
      final ble = makeConn(id: 'ble', type: ConnectionType.bleTnc);
      final aprsIs = makeConn(id: 'aprs_is', type: ConnectionType.aprsIs);
      await tx.sendLine('LINE');
      expect(serial.lastSentLine, 'LINE');
      expect(ble.lastSentLine, isNull);
      expect(aprsIs.lastSentLine, isNull);
    });

    test('forceVia: ConnectionType.aprsIs overrides hierarchy', () async {
      final serial = makeConn(id: 'serial', type: ConnectionType.serialTnc);
      final ble = makeConn(id: 'ble', type: ConnectionType.bleTnc);
      final aprsIs = makeConn(id: 'aprs_is', type: ConnectionType.aprsIs);
      await tx.sendLine('LINE', forceVia: ConnectionType.aprsIs);
      expect(aprsIs.lastSentLine, 'LINE');
      expect(serial.lastSentLine, isNull);
      expect(ble.lastSentLine, isNull);
    });
  });

  group('TxService — sendBeacon fan-out', () {
    setUp(() async {
      await baseSetUp();
      tx = TxService(registry, settings);
    });

    tearDown(() async {
      tx.dispose();
      for (final c in registry.all) {
        await c.dispose();
      }
    });

    test('beaconingEnabled=false excludes a connection from fan-out', () async {
      final aprsIs = makeConn(id: 'aprs_is', type: ConnectionType.aprsIs);
      final serial = makeConn(id: 'serial', type: ConnectionType.serialTnc);
      await aprsIs.setBeaconingEnabled(false);

      await tx.sendBeacon('=BEACON');

      expect(serial.lastSentLine, '=BEACON');
      expect(aprsIs.lastSentLine, isNull);
    });
  });
}
