import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_aprs/core/connection/ble_connection_impl.dart';
import 'package:meridian_aprs/core/connection/meridian_connection.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_kiss_tnc_transport.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Build raw AX.25 payload bytes (no KISS wrapper — matches what frameStream emits)
Uint8List _buildRawAx25(String src, String dst, String aprsInfo) {
  List<int> encodeAddr(String call, int ssid, {bool last = false}) {
    final bytes = List<int>.filled(7, 0);
    final padded = call.padRight(6);
    for (int i = 0; i < 6; i++) {
      bytes[i] = padded.codeUnitAt(i) << 1;
    }
    bytes[6] = ((ssid & 0x0F) << 1) | (last ? 0x01 : 0x00);
    return bytes;
  }

  final addr = <int>[...encodeAddr(dst, 0), ...encodeAddr(src, 0, last: true)];
  return Uint8List.fromList([...addr, 0x03, 0xF0, ...aprsInfo.codeUnits]);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late BleConnection conn;
  late FakeKissTncTransport fakeTransport;

  // We use a fake BluetoothDevice — the actual device object is never used
  // by BleConnection because the transportFactory intercepts it.
  final fakeDevice = BluetoothDevice.fromId('AA:BB:CC:DD:EE:FF');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeTransport = FakeKissTncTransport();
    conn = BleConnection();
    // Inject fake transport — factory ignores the device and returns the shared fake
    conn.transportFactory = (_) => fakeTransport;
  });

  tearDown(() async {
    await conn.dispose();
    await fakeTransport.close();
  });

  test('id, displayName, type are correct', () {
    expect(conn.id, 'ble_tnc');
    expect(conn.displayName, 'BLE TNC');
    expect(conn.type, ConnectionType.bleTnc);
  });

  test('initial state is disconnected', () {
    expect(conn.status, ConnectionStatus.disconnected);
    expect(conn.isConnected, isFalse);
  });

  test('connectToDevice transitions to connected', () async {
    await conn.connectToDevice(fakeDevice);
    expect(conn.isConnected, isTrue);
    expect(conn.status, ConnectionStatus.connected);
  });

  test('disconnect transitions to disconnected', () async {
    await conn.connectToDevice(fakeDevice);
    await conn.disconnect();
    expect(conn.isConnected, isFalse);
    expect(conn.status, ConnectionStatus.disconnected);
  });

  test('connectionState stream emits status transitions', () async {
    final states = <ConnectionStatus>[];
    conn.connectionState.listen(states.add);

    await conn.connectToDevice(fakeDevice);
    await conn.disconnect();
    await Future<void>.delayed(Duration.zero);

    expect(states, containsAll([ConnectionStatus.connected]));
  });

  test('lines stream emits APRS text from KISS-wrapped AX.25 frames', () async {
    final received = <String>[];
    conn.lines.listen(received.add);

    await conn.connectToDevice(fakeDevice);

    // frameStream emits raw AX.25 payload (KISS header already stripped)
    final rawAx25 = _buildRawAx25(
      'W1AW',
      'APZMDN',
      '!4903.50N/07201.75W>Test comment',
    );
    fakeTransport.simulateFrame(rawAx25);
    await Future<void>.delayed(Duration.zero);

    // The parser should have decoded the AX.25 frame into a rawLine
    expect(received, hasLength(1));
    expect(received.first, contains('W1AW'));
  });

  test('sendLine encodes to AX.25 and calls sendFrame', () async {
    await conn.connectToDevice(fakeDevice);
    await conn.sendLine('W1AW-9>APZMDN,TCPIP*:!4903.50N/07201.75W>Hello');
    expect(fakeTransport.sentFrames, hasLength(1));
  });

  test('beaconingEnabled defaults to true', () {
    expect(conn.beaconingEnabled, isTrue);
  });

  test('setBeaconingEnabled persists to SharedPreferences', () async {
    await conn.setBeaconingEnabled(false);
    expect(conn.beaconingEnabled, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('beacon_enabled_ble_tnc'), isFalse);
  });

  test('loadPersistedSettings restores beaconingEnabled', () async {
    SharedPreferences.setMockInitialValues({'beacon_enabled_ble_tnc': false});
    final conn2 = BleConnection();
    conn2.transportFactory = (_) => FakeKissTncTransport();
    await conn2.loadPersistedSettings();
    expect(conn2.beaconingEnabled, isFalse);
    await conn2.dispose();
  });

  group('reconnect', () {
    test('no reconnect attempt before first connect', () async {
      fakeTransport.connectThrows = true;
      // connect() was never called — no reconnect should happen
      expect(conn.status, ConnectionStatus.disconnected);
    });

    test('reconnect triggered on error after session established', () {
      fakeAsync((async) {
        // Connect and flush so session is established
        conn.connectToDevice(fakeDevice);
        async.flushMicrotasks();
        expect(conn.isConnected, isTrue);

        // Simulate unexpected disconnect
        fakeTransport.simulateUnexpectedDisconnect();
        // After the error event, _onTransportStatus fires (sync stream),
        // which calls scheduleReconnect — status becomes reconnecting
        expect(conn.status, ConnectionStatus.reconnecting);
      });
    });

    test('disconnect cancels pending reconnect', () async {
      await conn.connectToDevice(fakeDevice);
      fakeTransport.simulateUnexpectedDisconnect();
      await Future<void>.delayed(Duration.zero);
      // While reconnecting, user disconnects
      await conn.disconnect();
      expect(conn.status, ConnectionStatus.disconnected);
    });
  });
}
