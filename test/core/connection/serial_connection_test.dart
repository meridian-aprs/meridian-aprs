import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_aprs/core/connection/serial_connection_impl.dart';
import 'package:meridian_aprs/core/connection/meridian_connection.dart';
import 'package:meridian_aprs/core/transport/tnc_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_serial_kiss_transport.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _testConfig = TncConfig(port: '/dev/ttyUSB0', baudRate: 9600);

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
  late SerialConnection conn;
  late FakeSerialKissTransport fakeTransport;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeTransport = FakeSerialKissTransport();
    conn = SerialConnection();
    conn.transportFactory = (_) => fakeTransport;
  });

  tearDown(() async {
    await conn.dispose();
    await fakeTransport.close();
  });

  test('id, displayName, type are correct', () {
    expect(conn.id, 'serial_tnc');
    expect(conn.displayName, 'USB TNC');
    expect(conn.type, ConnectionType.serialTnc);
  });

  test('initial state is disconnected', () {
    expect(conn.status, ConnectionStatus.disconnected);
    expect(conn.isConnected, isFalse);
  });

  test('connectWithConfig transitions to connected', () async {
    await conn.connectWithConfig(_testConfig);
    expect(conn.isConnected, isTrue);
    expect(conn.status, ConnectionStatus.connected);
    expect(conn.activeConfig, _testConfig);
  });

  test('disconnect transitions to disconnected', () async {
    await conn.connectWithConfig(_testConfig);
    await conn.disconnect();
    expect(conn.isConnected, isFalse);
    expect(conn.status, ConnectionStatus.disconnected);
  });

  test('connectionState stream emits status transitions', () async {
    final states = <ConnectionStatus>[];
    conn.connectionState.listen(states.add);

    await conn.connectWithConfig(_testConfig);
    await conn.disconnect();
    await Future<void>.delayed(Duration.zero);

    expect(states, containsAll([ConnectionStatus.connected]));
  });

  test('lines stream emits APRS text from AX.25 frames', () async {
    final received = <String>[];
    conn.lines.listen(received.add);

    await conn.connectWithConfig(_testConfig);

    final rawAx25 = _buildRawAx25(
      'W1AW',
      'APZMDN',
      '!4903.50N/07201.75W>Test comment',
    );
    fakeTransport.simulateFrame(rawAx25);
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(1));
    expect(received.first, contains('W1AW'));
  });

  test('sendLine encodes to AX.25 and calls sendFrame', () async {
    await conn.connectWithConfig(_testConfig);
    await conn.sendLine('W1AW-9>APZMDN,TCPIP*:!4903.50N/07201.75W>Hello');
    expect(fakeTransport.sentFrames, hasLength(1));
  });

  test('connect() throws when no config is set', () async {
    await expectLater(conn.connect(), throwsStateError);
  });

  test('connect() failure sets error status and lastErrorMessage', () async {
    fakeTransport.connectThrows = true;
    await conn.connectWithConfig(_testConfig);
    expect(conn.status, ConnectionStatus.error);
    expect(conn.lastErrorMessage, isNotNull);
    expect(conn.lastErrorMessage, contains('/dev/ttyUSB0'));
  });

  test('beaconingEnabled defaults to true', () {
    expect(conn.beaconingEnabled, isTrue);
  });

  test('setBeaconingEnabled persists to SharedPreferences', () async {
    await conn.setBeaconingEnabled(false);
    expect(conn.beaconingEnabled, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('beacon_enabled_serial_tnc'), isFalse);
  });

  test('connectWithConfig persists TncConfig to SharedPreferences', () async {
    await conn.connectWithConfig(_testConfig);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tnc_port'), '/dev/ttyUSB0');
    expect(prefs.getInt('tnc_baud'), 9600);
  });

  test(
    'loadPersistedSettings restores beaconingEnabled and activeConfig',
    () async {
      SharedPreferences.setMockInitialValues({
        'beacon_enabled_serial_tnc': false,
        'tnc_port': '/dev/ttyACM0',
        'tnc_baud': 115200,
      });
      final conn2 = SerialConnection();
      conn2.transportFactory = (_) => FakeSerialKissTransport();
      await conn2.loadPersistedSettings();
      expect(conn2.beaconingEnabled, isFalse);
      expect(conn2.activeConfig?.port, '/dev/ttyACM0');
      expect(conn2.activeConfig?.baudRate, 115200);
      await conn2.dispose();
    },
  );

  test(
    'no reconnect on initial connect failure (session never connected)',
    () async {
      fakeTransport.connectThrows = true;
      await conn.connectWithConfig(_testConfig);
      // Reconnect only triggers after a successful session; first-time failure
      // stays at error with no retry timer.
      expect(conn.status, ConnectionStatus.error);
      expect(conn.hasScheduledRetry, isFalse);
    },
  );

  test('auto-reconnects after mid-session error', () async {
    // Establish a successful session first.
    await conn.connectWithConfig(_testConfig);
    expect(conn.status, ConnectionStatus.connected);

    // Simulate a transport error (e.g. USB glitch during PTT).
    fakeTransport.simulateUnexpectedDisconnect();
    await Future<void>.delayed(Duration.zero);

    // Should now be scheduling a reconnect, not stuck at error.
    expect(conn.status, ConnectionStatus.reconnecting);
    expect(conn.hasScheduledRetry, isTrue);

    // Clean up before the timer fires.
    await conn.disconnect();
    expect(conn.status, ConnectionStatus.disconnected);
    expect(conn.hasScheduledRetry, isFalse);
  });
}
