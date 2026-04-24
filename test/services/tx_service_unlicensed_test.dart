/// Tests that [TxService] hard-rejects all TX when the user is unlicensed.
///
/// Also verifies that [AprsIsConnection] substitutes N0CALL/-1 in the login
/// line when [StationSettingsService.isLicensed] is false — see ADR-044/045.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meridian_aprs/core/connection/aprs_is_connection.dart';
import 'package:meridian_aprs/core/connection/connection_credentials.dart';
import 'package:meridian_aprs/core/connection/connection_registry.dart';
import 'package:meridian_aprs/core/transport/aprs_is_transport.dart';
import 'package:meridian_aprs/services/station_settings_service.dart';
import 'package:meridian_aprs/services/tx_service.dart';

import '../helpers/fake_meridian_connection.dart';
import '../helpers/fake_secure_credential_store.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Minimal fake transport that records updateCredentials and sendLine calls.
class _CapturingAprsIsTransport extends AprsIsTransport {
  _CapturingAprsIsTransport()
    : super(host: 'fake.host', port: 0, loginLine: 'user NOCALL pass -1\r\n');

  final _linesCtrl = StreamController<String>.broadcast();
  final _stateCtrl = StreamController<ConnectionStatus>.broadcast();
  ConnectionStatus _status = ConnectionStatus.disconnected;

  final List<String> capturedLoginLines = [];
  final List<String> sentLines = [];

  @override
  Stream<String> get lines => _linesCtrl.stream;

  @override
  Stream<ConnectionStatus> get connectionState => _stateCtrl.stream;

  @override
  ConnectionStatus get currentStatus => _status;

  @override
  void updateCredentials({required String loginLine, String? filterLine}) {
    capturedLoginLines.add(loginLine);
    super.updateCredentials(loginLine: loginLine, filterLine: filterLine);
  }

  @override
  Future<void> connect() async {
    _status = ConnectionStatus.connected;
    _stateCtrl.add(ConnectionStatus.connected);
  }

  @override
  Future<void> disconnect() async {
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
}

// ---------------------------------------------------------------------------
// TxService unlicensed rejection tests
// ---------------------------------------------------------------------------

void main() {
  group('TxService — unlicensed rejection', () {
    late SharedPreferences prefs;
    late StationSettingsService settings;
    late ConnectionRegistry registry;
    late FakeMeridianConnection conn;
    late List<String> sentViaConn;
    late TxService tx;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'user_callsign': 'W1AW',
        'user_ssid': 9,
        // isLicensed defaults to false when key is absent
      });
      prefs = await SharedPreferences.getInstance();
      settings = StationSettingsService(
        prefs,
        store: FakeSecureCredentialStore(),
      );

      registry = ConnectionRegistry();
      sentViaConn = [];
      conn = _TrackingFakeConnection(
        id: 'aprs_is',
        displayName: 'APRS-IS',
        type: ConnectionType.aprsIs,
        sentLines: sentViaConn,
      );
      registry.register(conn);
      conn.setStatus(ConnectionStatus.connected);

      tx = TxService(registry, settings);
    });

    tearDown(() async {
      tx.dispose();
      await conn.dispose();
    });

    test('sendBeacon is a no-op when isLicensed == false', () async {
      expect(settings.isLicensed, isFalse);
      await tx.sendBeacon('!1234.56N/12345.67W>test');
      expect(sentViaConn, isEmpty);
    });

    test('sendLine is a no-op when isLicensed == false', () async {
      expect(settings.isLicensed, isFalse);
      await tx.sendLine('!1234.56N/12345.67W>test');
      expect(sentViaConn, isEmpty);
    });

    test('sendBeacon forwards when isLicensed == true', () async {
      await settings.setIsLicensed(true);
      // beaconingEnabled defaults to true on FakeMeridianConnection
      await tx.sendBeacon('!1234.56N/12345.67W>test');
      expect(sentViaConn, hasLength(1));
    });

    test('sendLine forwards when isLicensed == true', () async {
      await settings.setIsLicensed(true);
      await tx.sendLine('!1234.56N/12345.67W>test');
      expect(sentViaConn, hasLength(1));
    });
  });

  // ---------------------------------------------------------------------------
  // AprsIsConnection — N0CALL/-1 login substitution
  // ---------------------------------------------------------------------------

  group('AprsIsConnection — N0CALL/-1 when unlicensed', () {
    late _CapturingAprsIsTransport transport;
    late AprsIsConnection conn;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      transport = _CapturingAprsIsTransport();
      conn = AprsIsConnection(
        transport,
        credentials: const ConnectionCredentials(
          callsign: 'W1AW',
          ssid: 9,
          passcode: '12345',
          isLicensed: false,
        ),
      );
    });

    tearDown(() async {
      await conn.dispose();
    });

    test('connect() applies N0CALL/-1 override when unlicensed', () async {
      await conn.connect();
      // Override pushes a N0CALL/-1 login line into the transport on connect.
      expect(transport.capturedLoginLines, isNotEmpty);
      expect(transport.capturedLoginLines.last, contains('N0CALL'));
      expect(transport.capturedLoginLines.last, contains('-1'));
    });

    test('connect() does NOT force N0CALL when licensed', () async {
      conn.setCredentials(
        const ConnectionCredentials(
          callsign: 'W1AW',
          ssid: 9,
          passcode: '12345',
          isLicensed: true,
        ),
      );
      await conn.connect();
      expect(transport.capturedLoginLines.last, contains('W1AW-9'));
      expect(transport.capturedLoginLines.last, contains('12345'));
      expect(transport.capturedLoginLines.last, isNot(contains('N0CALL')));
    });

    test(
      'setCredentials() applies N0CALL/-1 override when unlicensed',
      () async {
        conn.setCredentials(
          const ConnectionCredentials(
            callsign: 'W1AW',
            ssid: 9,
            passcode: '12345',
            isLicensed: false,
          ),
        );
        expect(
          transport.capturedLoginLines.any((l) => l.contains('N0CALL')),
          isTrue,
        );
        expect(
          transport.capturedLoginLines.any((l) => l.contains('-1')),
          isTrue,
        );
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Tracking fake connection — records sendLine calls
// ---------------------------------------------------------------------------

class _TrackingFakeConnection extends FakeMeridianConnection {
  _TrackingFakeConnection({
    required super.id,
    required super.displayName,
    required super.type,
    required this.sentLines,
  });

  final List<String> sentLines;

  @override
  Future<void> sendLine(String aprsLine, {List<String>? digipeaterPath}) async {
    sentLines.add(aprsLine);
  }
}
