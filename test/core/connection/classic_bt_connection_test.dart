import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_aprs/core/connection/classic_bt_connection_impl.dart';
import 'package:meridian_aprs/core/connection/meridian_connection.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_classic_bt_tnc_transport.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _testAddress = '00:11:22:33:44:55';
const _testName = 'TH-D75';

// Build raw AX.25 payload bytes (no KISS wrapper — matches frameStream output).
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
  late ClassicBtConnection conn;
  late FakeClassicBtTncTransport fakeTransport;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeTransport = FakeClassicBtTncTransport();
    conn = ClassicBtConnection();
    conn.transportFactory = (_) => fakeTransport;
  });

  tearDown(() async {
    await conn.dispose();
    await fakeTransport.close();
  });

  test('id, displayName, type are correct', () {
    expect(conn.id, 'classic_bt_tnc');
    expect(conn.displayName, 'Classic BT');
    expect(conn.type, ConnectionType.classicBtTnc);
  });

  test('initial state is disconnected', () {
    expect(conn.status, ConnectionStatus.disconnected);
    expect(conn.isConnected, isFalse);
  });

  test('connectToDevice transitions to connected', () async {
    await conn.connectToDevice(_testAddress, name: _testName);
    expect(conn.isConnected, isTrue);
    expect(conn.status, ConnectionStatus.connected);
    expect(conn.deviceAddress, _testAddress);
    expect(conn.deviceName, _testName);
  });

  test('disconnect transitions to disconnected', () async {
    await conn.connectToDevice(_testAddress);
    await conn.disconnect();
    expect(conn.isConnected, isFalse);
    expect(conn.status, ConnectionStatus.disconnected);
  });

  test('connectionState stream emits status transitions', () async {
    final states = <ConnectionStatus>[];
    conn.connectionState.listen(states.add);

    await conn.connectToDevice(_testAddress);
    await conn.disconnect();
    await Future<void>.delayed(Duration.zero);

    expect(states, containsAll([ConnectionStatus.connected]));
  });

  test('lines stream emits APRS text from AX.25 frames', () async {
    final received = <String>[];
    conn.lines.listen(received.add);

    await conn.connectToDevice(_testAddress);

    final rawAx25 = _buildRawAx25(
      'W1AW',
      'APMDN0',
      '!4903.50N/07201.75W>Test comment',
    );
    fakeTransport.simulateFrame(rawAx25);
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(1));
    expect(received.first, contains('W1AW'));
  });

  test('sendLine encodes to AX.25 and calls sendFrame', () async {
    await conn.connectToDevice(_testAddress);
    await conn.sendLine('W1AW-9>APMDN0,TCPIP*:!4903.50N/07201.75W>Hello');
    expect(fakeTransport.sentFrames, hasLength(1));
  });

  test('connect() throws when no device is set', () async {
    await expectLater(conn.connect(), throwsStateError);
  });

  test('connect() failure sets error status and lastErrorMessage', () async {
    fakeTransport.connectThrows = true;
    await conn.connectToDevice(_testAddress, name: _testName);
    expect(conn.status, ConnectionStatus.error);
    expect(conn.lastErrorMessage, isNotNull);
    expect(conn.lastErrorMessage, contains(_testName));
  });

  test('beaconingEnabled defaults to true', () {
    expect(conn.beaconingEnabled, isTrue);
  });

  test('setBeaconingEnabled persists to SharedPreferences', () async {
    await conn.setBeaconingEnabled(false);
    expect(conn.beaconingEnabled, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('beacon_enabled_classic_bt_tnc'), isFalse);
  });

  test('connectToDevice persists address and name', () async {
    await conn.connectToDevice(_testAddress, name: _testName);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('classic_bt_address'), _testAddress);
    expect(prefs.getString('classic_bt_name'), _testName);
  });

  test('loadPersistedSettings restores beaconing and device', () async {
    SharedPreferences.setMockInitialValues({
      'beacon_enabled_classic_bt_tnc': false,
      'classic_bt_address': 'AA:BB:CC:DD:EE:FF',
      'classic_bt_name': 'Mobilinkd',
    });
    final conn2 = ClassicBtConnection();
    conn2.transportFactory = (_) => FakeClassicBtTncTransport();
    await conn2.loadPersistedSettings();
    expect(conn2.beaconingEnabled, isFalse);
    expect(conn2.deviceAddress, 'AA:BB:CC:DD:EE:FF');
    expect(conn2.deviceName, 'Mobilinkd');
    await conn2.dispose();
  });

  test(
    'no reconnect on initial connect failure (session never connected)',
    () async {
      fakeTransport.connectThrows = true;
      await conn.connectToDevice(_testAddress);
      expect(conn.status, ConnectionStatus.error);
      expect(conn.hasScheduledRetry, isFalse);
    },
  );

  test('auto-reconnects after mid-session error', () async {
    await conn.connectToDevice(_testAddress);
    expect(conn.status, ConnectionStatus.connected);

    // Simulate a transport-level error (e.g. RFCOMM link drop).
    fakeTransport.simulateUnexpectedDisconnect();
    await Future<void>.delayed(Duration.zero);

    expect(conn.status, ConnectionStatus.reconnecting);
    expect(conn.hasScheduledRetry, isTrue);

    await conn.disconnect();
    expect(conn.status, ConnectionStatus.disconnected);
    expect(conn.hasScheduledRetry, isFalse);
  });
}
