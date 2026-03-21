import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_aprs/core/transport/aprs_transport.dart';
import 'package:meridian_aprs/core/transport/kiss_framer.dart';
import 'package:meridian_aprs/core/transport/serial_kiss_transport.dart';
import 'package:meridian_aprs/core/transport/serial_port_adapter.dart';
import 'package:meridian_aprs/core/transport/tnc_config.dart';
import 'package:meridian_aprs/core/transport/tnc_preset.dart';

// ---------------------------------------------------------------------------
// Helpers — reuse the AX.25 frame-building logic from the pipeline test.
// ---------------------------------------------------------------------------

/// Encode a callsign + SSID into the 7-byte AX.25 address field format.
List<int> _encodeAddr(String callsign, int ssid, {bool last = false}) {
  final bytes = List<int>.filled(7, 0);
  final padded = callsign.padRight(6);
  for (int i = 0; i < 6; i++) {
    bytes[i] = padded.codeUnitAt(i) << 1;
  }
  bytes[6] = ((ssid & 0x0F) << 1) | (last ? 0x01 : 0x00);
  return bytes;
}

/// Build a complete KISS-wrapped AX.25 UI frame.
Uint8List _buildKissFrame(String src, String dst, String aprsInfo) {
  final addrBytes = <int>[
    ..._encodeAddr(dst, 0),
    ..._encodeAddr(src, 0, last: true),
  ];
  final frame = [...addrBytes, 0x03, 0xF0, ...aprsInfo.codeUnits];
  return KissFramer.encode(Uint8List.fromList(frame));
}

// ---------------------------------------------------------------------------
// Fake adapter
// ---------------------------------------------------------------------------

class FakeSerialPortAdapter implements SerialPortAdapter {
  final _byteController = StreamController<Uint8List>();
  bool openCalled = false;
  bool configureCalled = false;
  bool closeCalled = false;
  bool openReturns = true;

  @override
  bool open() {
    openCalled = true;
    return openReturns;
  }

  @override
  void configure({
    required int baudRate,
    required int dataBits,
    required int stopBits,
    required String parity,
    required bool hardwareFlowControl,
  }) {
    configureCalled = true;
  }

  @override
  Stream<Uint8List> get byteStream => _byteController.stream;

  @override
  void close() {
    closeCalled = true;
    if (!_byteController.isClosed) {
      _byteController.close();
    }
  }

  /// Push bytes into the transport as if received from the serial port.
  void pushBytes(List<int> bytes) {
    if (!_byteController.isClosed) {
      _byteController.add(Uint8List.fromList(bytes));
    }
  }

  /// Simulate the port being unplugged (stream closes without close() being
  /// called on the adapter — the done event fires on its own).
  Future<void> simulateDisconnect() => _byteController.close();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SerialKissTransport', () {
    late FakeSerialPortAdapter fakeAdapter;
    late SerialKissTransport transport;
    late TncConfig config;

    setUp(() {
      config = TncConfig.fromPreset(
        TncPreset.mobilinkdTnc4,
        port: '/dev/ttyFAKE',
      );
      fakeAdapter = FakeSerialPortAdapter();
      transport = SerialKissTransport(config, adapter: fakeAdapter);
    });

    tearDown(() async {
      await transport.disconnect();
    });

    // 1 -----------------------------------------------------------------------
    test('initial status is disconnected', () {
      expect(transport.currentStatus, ConnectionStatus.disconnected);
    });

    // 2 -----------------------------------------------------------------------
    test('connect() transitions through connecting → connected', () async {
      final statesFuture = transport.connectionState.take(2).toList();

      await transport.connect();

      final states = await statesFuture;
      expect(states, [ConnectionStatus.connecting, ConnectionStatus.connected]);
      expect(fakeAdapter.openCalled, isTrue);
      expect(fakeAdapter.configureCalled, isTrue);
    });

    // 3 -----------------------------------------------------------------------
    test('connect() transitions to error when port open fails', () async {
      fakeAdapter.openReturns = false;

      // connect() rethrows after setting status to error.
      await expectLater(transport.connect(), throwsException);

      expect(transport.currentStatus, ConnectionStatus.error);
    });

    // 4 -----------------------------------------------------------------------
    test('disconnect() transitions to disconnected', () async {
      await transport.connect();
      await transport.disconnect();

      expect(transport.currentStatus, ConnectionStatus.disconnected);
      expect(fakeAdapter.closeCalled, isTrue);
    });

    // 5 -----------------------------------------------------------------------
    test(
      'lines stream emits decoded APRS line when valid KISS frame received',
      () async {
        await transport.connect();

        final lines = <String>[];
        final sub = transport.lines.listen(lines.add);

        final kissFrameBytes = _buildKissFrame(
          'W1AW',
          'APRS',
          '!4903.50N/07201.75W-Test',
        );
        fakeAdapter.pushBytes(kissFrameBytes);

        // Allow microtasks to propagate through the stream pipeline.
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        await sub.cancel();

        expect(lines, isNotEmpty);
        expect(lines.first, contains('W1AW'));
      },
    );

    // 6 -----------------------------------------------------------------------
    test('port disconnect (stream done) transitions to disconnected', () async {
      await transport.connect();

      // Listen for the state change triggered by the done event.
      final stateAfterDoneFuture = transport.connectionState.firstWhere(
        (s) => s == ConnectionStatus.disconnected,
      );

      await fakeAdapter.simulateDisconnect();
      await Future<void>.delayed(Duration.zero);

      expect(
        await stateAfterDoneFuture.timeout(const Duration(seconds: 1)),
        ConnectionStatus.disconnected,
      );
      expect(transport.currentStatus, ConnectionStatus.disconnected);
    });
  });
}
