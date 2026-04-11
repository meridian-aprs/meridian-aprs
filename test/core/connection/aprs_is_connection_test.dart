import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_aprs/core/connection/aprs_is_connection.dart';
import 'package:meridian_aprs/core/connection/meridian_connection.dart';
import 'package:meridian_aprs/core/transport/aprs_is_transport.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Fake transport — extends AprsIsTransport to satisfy the constructor type
// ---------------------------------------------------------------------------

class _FakeAprsIsTransport extends AprsIsTransport {
  _FakeAprsIsTransport()
    : super(host: 'fake.host', port: 0, loginLine: 'user NOCALL pass -1\r\n');

  final _linesCtrl = StreamController<String>.broadcast();
  final _stateCtrl = StreamController<ConnectionStatus>.broadcast();
  ConnectionStatus _status = ConnectionStatus.disconnected;

  bool connectCalled = false;
  bool disconnectCalled = false;
  final List<String> sentLines = [];

  @override
  Stream<String> get lines => _linesCtrl.stream;

  @override
  Stream<ConnectionStatus> get connectionState => _stateCtrl.stream;

  @override
  ConnectionStatus get currentStatus => _status;

  @override
  Future<void> connect() async {
    connectCalled = true;
    _status = ConnectionStatus.connected;
    _stateCtrl.add(ConnectionStatus.connected);
  }

  @override
  Future<void> disconnect() async {
    disconnectCalled = true;
    _status = ConnectionStatus.disconnected;
    _stateCtrl.add(ConnectionStatus.disconnected);
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _linesCtrl.close();
    await _stateCtrl.close();
  }

  @override
  void sendLine(String line) => sentLines.add(line);

  void pushLine(String line) => _linesCtrl.add(line);
  void pushStatus(ConnectionStatus s) {
    _status = s;
    _stateCtrl.add(s);
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _FakeAprsIsTransport transport;
  late AprsIsConnection conn;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    transport = _FakeAprsIsTransport();
    conn = AprsIsConnection(transport);
  });

  tearDown(() async {
    await conn.dispose();
  });

  test('id, displayName, type are correct', () {
    expect(conn.id, 'aprs_is');
    expect(conn.displayName, 'APRS-IS');
    expect(conn.type, ConnectionType.aprsIs);
  });

  test('initial status is disconnected', () {
    expect(conn.status, ConnectionStatus.disconnected);
    expect(conn.isConnected, isFalse);
  });

  test('connect() delegates to transport and updates status', () async {
    await conn.connect();
    expect(transport.connectCalled, isTrue);
    expect(conn.status, ConnectionStatus.connected);
    expect(conn.isConnected, isTrue);
  });

  test('disconnect() delegates to transport', () async {
    await conn.connect();
    await conn.disconnect();
    expect(transport.disconnectCalled, isTrue);
    expect(conn.isConnected, isFalse);
  });

  test('connectionState stream forwards transport events', () async {
    final states = <ConnectionStatus>[];
    conn.connectionState.listen(states.add);
    transport.pushStatus(ConnectionStatus.connecting);
    transport.pushStatus(ConnectionStatus.connected);
    await Future<void>.delayed(Duration.zero);
    expect(states, [ConnectionStatus.connecting, ConnectionStatus.connected]);
  });

  test('lines stream forwards transport lines', () async {
    final received = <String>[];
    conn.lines.listen(received.add);
    transport.pushLine('W1AW>APRS,TCPIP*:!1234.56N/01234.56W>Comment');
    await Future<void>.delayed(Duration.zero);
    expect(received, hasLength(1));
    expect(received.first, contains('W1AW'));
  });

  test('sendLine appends \\r\\n and delegates', () async {
    await conn.connect();
    await conn.sendLine('W1AW>APZMDN:hello');
    expect(transport.sentLines, ['W1AW>APZMDN:hello\r\n']);
  });

  test('beaconingEnabled defaults to true', () {
    expect(conn.beaconingEnabled, isTrue);
  });

  test('setBeaconingEnabled persists to SharedPreferences', () async {
    await conn.setBeaconingEnabled(false);
    expect(conn.beaconingEnabled, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('beacon_enabled_aprs_is'), isFalse);
  });

  test('loadPersistedSettings restores beaconingEnabled from prefs', () async {
    SharedPreferences.setMockInitialValues({'beacon_enabled_aprs_is': false});
    final conn2 = AprsIsConnection(_FakeAprsIsTransport());
    await conn2.loadPersistedSettings();
    expect(conn2.beaconingEnabled, isFalse);
    await conn2.dispose();
  });

  test('updateFilter sends correct filter line', () async {
    conn.updateFilter(47.61, -122.33, radiusKm: 100);
    expect(transport.sentLines, ['#filter r/47.61/-122.33/100\r\n']);
  });
}
