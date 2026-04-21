import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_aprs/core/connection/aprs_is_connection.dart';
import 'package:meridian_aprs/core/connection/aprs_is_filter_config.dart';
import 'package:meridian_aprs/core/connection/lat_lng_box.dart';
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
    await conn.sendLine('W1AW>APMDN0:hello');
    expect(transport.sentLines, ['W1AW>APMDN0:hello\r\n']);
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

  // ---------------------------------------------------------------------------
  // Filter configuration
  // ---------------------------------------------------------------------------

  test('filterConfig defaults to Regional (v0.12 parity)', () {
    expect(conn.filterConfig, AprsIsFilterConfig.regional);
  });

  test('setFilterConfig updates in-memory config without I/O', () {
    conn.setFilterConfig(AprsIsFilterConfig.wide);
    expect(conn.filterConfig, AprsIsFilterConfig.wide);
    // Setting config does not send anything to the server on its own.
    expect(transport.sentLines, isEmpty);
  });

  test('updateFilter with Regional matches pre-Phase-3 output', () {
    // Same 1°×1° box as the legacy test: Seattle area.
    const box = LatLngBox(north: 48.0, south: 47.0, east: -122.0, west: -123.0);
    conn.setFilterConfig(AprsIsFilterConfig.regional);
    conn.updateFilter(box);

    // Regional = 25% pad, 50 km min. padded south=46.75, north=48.25,
    // west=-123.25, east=-121.75. minHalf = 50/111 ≈ 0.4505, formatted
    // to 2dp = 0.45 — same as the v0.12 hardcoded value.
    expect(
      transport.sentLines.single,
      '#filter a/48.25/-123.25/46.75/-121.75\r\n',
    );
  });

  test('updateFilter produces different strings per preset', () {
    const box = LatLngBox(north: 48.0, south: 47.0, east: -122.0, west: -123.0);

    conn.setFilterConfig(AprsIsFilterConfig.local);
    conn.updateFilter(box);
    final local = transport.sentLines.last;

    conn.setFilterConfig(AprsIsFilterConfig.regional);
    conn.updateFilter(box);
    final regional = transport.sentLines.last;

    conn.setFilterConfig(AprsIsFilterConfig.wide);
    conn.updateFilter(box);
    final wide = transport.sentLines.last;

    expect(local, isNot(equals(regional)));
    expect(regional, isNot(equals(wide)));
    expect(local, isNot(equals(wide)));
  });

  test('updateFilter honours pad percentage', () {
    // A tiny box so the minimum radius does NOT kick in and we see the
    // pad percentage effect cleanly.
    const box = LatLngBox(north: 48.0, south: 40.0, east: -120.0, west: -130.0);

    const tightPad = AprsIsFilterConfig(
      preset: AprsIsFilterPreset.custom,
      padPct: 0.0,
      minRadiusKm: 10,
    );
    conn.setFilterConfig(tightPad);
    conn.updateFilter(box);
    // 0% pad, small min radius → bounding box ≈ original.
    expect(
      transport.sentLines.last,
      '#filter a/48.00/-130.00/40.00/-120.00\r\n',
    );
  });

  test('updateFilter passes explicit config override', () {
    const box = LatLngBox(north: 48.0, south: 47.0, east: -122.0, west: -123.0);
    // Registered config is Regional, but we override with Wide on this call.
    conn.setFilterConfig(AprsIsFilterConfig.regional);
    conn.updateFilter(box, config: AprsIsFilterConfig.wide);

    // Wide = 50% pad, 150 km min. For a 1°×1° box centred on 47.5°N,
    // the minimum half-extent (150/111 ≈ 1.35°) dominates the 50% pad
    // (0.5°), so the effective north is 47.5 + 1.35 = 48.85.
    final parts = transport.sentLines.last
        .replaceFirst('#filter a/', '')
        .replaceAll('\r\n', '')
        .split('/');
    expect(double.parse(parts[0]), greaterThan(48.8)); // north
    expect(double.parse(parts[2]), lessThan(46.2)); // south
  });

  test('defaultFilterLine uses 167 km floor regardless of preset', () {
    // Local has 25 km min, but defaultFilterLine is the no-viewport
    // fallback — it enforces a 167 km floor so the initial feed is useful.
    final line = AprsIsConnection.defaultFilterLine(
      47.5,
      -122.5,
      config: AprsIsFilterConfig.local,
    );
    // 167 km / 111 ≈ 1.505° half-extent.
    expect(line, startsWith('#filter a/49.00/-124.00'));
  });

  test('defaultFilterLine honours Wide above the floor', () {
    // Wide = 150 km min — still below the 167 km floor, so it uses 167.
    final line = AprsIsConnection.defaultFilterLine(
      47.5,
      -122.5,
      config: AprsIsFilterConfig.wide,
    );
    expect(line, startsWith('#filter a/49.00/-124.00'));
  });

  test(
    'updateFilter sends area filter line (a/ = geographic bounding box)',
    () async {
      // A 1°×1° box centred on Seattle, padded 25% each edge.
      // south=47.0, north=48.0, west=-123.0, east=-122.0
      // padded: s=46.75, n=48.25, w=-123.25, e=-121.75
      // minimum half-extent check: midLat=47.5, midLon=-122.5 → already >0.45
      // a/ format: a/latN/lonW/latS/lonE → a/48.25/-123.25/46.75/-121.75
      const box = LatLngBox(
        north: 48.0,
        south: 47.0,
        east: -122.0,
        west: -123.0,
      );
      conn.updateFilter(box);
      expect(transport.sentLines.length, 1);
      expect(transport.sentLines.first, startsWith('#filter a/'));
      expect(transport.sentLines.first, endsWith('\r\n'));
      // Verify N/W/S/E order: north (48.25) appears before south (46.75).
      final parts = transport.sentLines.first
          .replaceFirst('#filter a/', '')
          .replaceAll('\r\n', '')
          .split('/');
      expect(
        double.parse(parts[0]),
        greaterThan(double.parse(parts[2])),
      ); // N > S
      expect(double.parse(parts[1]), lessThan(double.parse(parts[3]))); // W < E
    },
  );
}
