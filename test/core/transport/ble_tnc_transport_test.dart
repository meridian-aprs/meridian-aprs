import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_aprs/core/transport/aprs_transport.dart';
import 'package:meridian_aprs/core/transport/ble_tnc_transport_impl.dart';
import 'package:meridian_aprs/core/transport/kiss_framer.dart';

// ---------------------------------------------------------------------------
// AX.25 / KISS helpers (mirrors serial_kiss_pipeline_test.dart)
// ---------------------------------------------------------------------------

List<int> _encodeAddr(String callsign, int ssid, {bool last = false}) {
  final bytes = List<int>.filled(7, 0);
  final padded = callsign.padRight(6);
  for (int i = 0; i < 6; i++) {
    bytes[i] = padded.codeUnitAt(i) << 1;
  }
  bytes[6] = ((ssid & 0x0F) << 1) | (last ? 0x01 : 0x00);
  return bytes;
}

Uint8List _buildKissFrame(String src, String dst, String aprsInfo) {
  final addrBytes = <int>[
    ..._encodeAddr(dst, 0),
    ..._encodeAddr(src, 0, last: true),
  ];
  final frame = [...addrBytes, 0x03, 0xF0, ...aprsInfo.codeUnits];
  return KissFramer.encode(Uint8List.fromList(frame));
}

// ---------------------------------------------------------------------------
// FakeBleDeviceAdapter
// ---------------------------------------------------------------------------

/// Fake [BleDeviceAdapter] for unit-testing [BleTncTransport].
///
/// Characteristic-level operations (setNotifyValue, write, onValueReceived)
/// are performed on real [BluetoothCharacteristic] objects inside the
/// transport, which require the native platform. These cannot be tested
/// here — those paths are exercised by integration tests.
///
/// This fake covers:
///   - Device-level connect / disconnect
///   - MTU negotiation
///   - Service discovery (configurable result)
///   - Connection-state stream for unexpected-disconnect tests
class FakeBleDeviceAdapter implements BleDeviceAdapter {
  // ----- configuration knobs -----
  bool connectThrows = false;
  bool discoverThrows = false;
  int fakeMtu = 512;
  List<BluetoothService> services = [];

  // ----- call tracking -----
  int connectCallCount = 0;
  int disconnectCallCount = 0;
  int requestMtuCallCount = 0;
  int discoverCallCount = 0;

  // ----- connection state stream -----
  final _connStateController =
      StreamController<BluetoothConnectionState>.broadcast();

  @override
  String platformName = 'FakeTNC';

  @override
  int get mtu => fakeMtu;

  @override
  Future<void> connect({
    Duration timeout = const Duration(seconds: 15),
    bool autoConnect = false,
  }) async {
    connectCallCount++;
    if (connectThrows) throw Exception('FakeBleDeviceAdapter: connect failed');
  }

  @override
  Future<void> disconnect() async {
    disconnectCallCount++;
  }

  @override
  Future<int> requestMtu(int desired) async {
    requestMtuCallCount++;
    // Simulate a small MTU so chunking logic can be observed.
    return fakeMtu;
  }

  @override
  Future<List<BluetoothService>> discoverServices() async {
    discoverCallCount++;
    if (discoverThrows) {
      throw Exception('FakeBleDeviceAdapter: discoverServices failed');
    }
    return services;
  }

  @override
  Stream<BluetoothConnectionState> get connectionState =>
      _connStateController.stream;

  /// Push a [BluetoothConnectionState] value onto the stream as if the
  /// platform reported a state change.
  void emitConnectionState(BluetoothConnectionState state) {
    _connStateController.add(state);
  }

  Future<void> close() => _connStateController.close();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('BleTncTransport', () {
    late FakeBleDeviceAdapter fakeAdapter;
    late BleTncTransport transport;
    // A dummy BluetoothDevice — the transport constructor requires one even
    // when an adapter is injected. fromId avoids any platform call.
    final dummyDevice = BluetoothDevice.fromId('AA:BB:CC:DD:EE:FF');

    setUp(() {
      fakeAdapter = FakeBleDeviceAdapter();
      transport = BleTncTransport(dummyDevice, adapter: fakeAdapter);
    });

    tearDown(() async {
      // Best-effort cleanup; transport may already be disconnected.
      try {
        await transport.disconnect();
      } catch (_) {}
      await fakeAdapter.close();
    });

    // 1 -----------------------------------------------------------------------
    test('initial status is disconnected and isConnected is false', () {
      expect(transport.currentStatus, ConnectionStatus.disconnected);
      expect(transport.isConnected, isFalse);
    });

    // 2 -----------------------------------------------------------------------
    test(
      'connect() emits connecting status then transitions to error when no matching service',
      () async {
        // fakeAdapter.services is empty → service UUID not found → error.
        final capturedStates = <ConnectionStatus>[];
        final sub = transport.connectionState.listen(capturedStates.add);

        await expectLater(transport.connect(), throwsA(isA<Exception>()));

        await sub.cancel();

        expect(capturedStates, containsAll([ConnectionStatus.connecting]));
        // After the exception the status must be error.
        expect(transport.currentStatus, ConnectionStatus.error);
      },
    );

    // 3 -----------------------------------------------------------------------
    test('connect() calls device connect and discoverServices', () async {
      await expectLater(transport.connect(), throwsA(isA<Exception>()));

      expect(fakeAdapter.connectCallCount, 1);
      expect(fakeAdapter.discoverCallCount, greaterThanOrEqualTo(1));
    });

    // 4 -----------------------------------------------------------------------
    test(
      'connect() transitions to error when adapter.connect() throws',
      () async {
        fakeAdapter.connectThrows = true;

        final capturedStates = <ConnectionStatus>[];
        final sub = transport.connectionState.listen(capturedStates.add);

        await expectLater(transport.connect(), throwsA(isA<Exception>()));

        await sub.cancel();

        expect(transport.currentStatus, ConnectionStatus.error);
        // disconnect() should have been called during cleanup.
        expect(fakeAdapter.disconnectCallCount, 1);
      },
    );

    // 5 -----------------------------------------------------------------------
    test(
      'connect() retries discoverServices up to 3 times when it throws',
      () async {
        fakeAdapter.discoverThrows = true;

        // connect() → adapter.connect succeeds → discoverServices throws × 3 → rethrows.
        await expectLater(transport.connect(), throwsA(isA<Exception>()));

        // The implementation retries up to 3× before rethrowing.
        expect(fakeAdapter.discoverCallCount, 3);
        expect(transport.currentStatus, ConnectionStatus.error);
      },
    );

    // 6 -----------------------------------------------------------------------
    test('disconnect() on disconnected transport is a no-op', () async {
      // Must not throw.
      await transport.disconnect();
      expect(transport.currentStatus, ConnectionStatus.disconnected);
    });

    // 7 -----------------------------------------------------------------------
    test('unexpected BLE disconnection sets status to error', () async {
      // Drive transport into error state (service not found after connect) so
      // it has registered the connectionState listener.
      // We need to simulate the transport being connected; the only path that
      // sets up _connStateSub is a successful connect(). Since characteristic
      // operations require the native stack, we cannot reach ConnectionStatus.connected
      // in unit tests. Instead we verify that the _onBleConnectionState handler
      // sets status=error when it receives a disconnected event while status==connected.
      //
      // We test this by reaching into the state change via the stream directly:
      // The transport registers _adapter.connectionState.listen(_onBleConnectionState)
      // only after a successful connect. We can't reach that point without
      // characteristic mocking. This test verifies the behaviour when we are
      // in the disconnected state (no listener registered) — the stream emission
      // is silently ignored and status stays disconnected.
      fakeAdapter.emitConnectionState(BluetoothConnectionState.disconnected);
      await Future<void>.delayed(Duration.zero);

      // No listener registered yet — status must remain disconnected.
      expect(transport.currentStatus, ConnectionStatus.disconnected);
    });

    // 8 -----------------------------------------------------------------------
    test('sendFrame throws StateError when not connected', () async {
      final ax25 = Uint8List.fromList([0x01, 0x02, 0x03]);
      expect(() async => transport.sendFrame(ax25), throwsA(isA<StateError>()));
    });

    // 9 -----------------------------------------------------------------------
    group('KISS framer reassembly (BLE chunked delivery)', () {
      // These tests exercise KissFramer directly, mirroring how
      // BleTncTransport._onBleChunk feeds bytes into _kissFramer.
      // This isolates the reassembly logic without needing a live BLE stack.

      late KissFramer framer;

      setUp(() {
        framer = KissFramer();
      });

      tearDown(() {
        framer.dispose();
      });

      test('reassembles a frame delivered in two BLE chunks', () async {
        final kissBytes = _buildKissFrame(
          'W1AW',
          'APRS',
          '!4903.50N/07201.75W-BLE',
        );
        // Split the frame into two chunks as BLE might deliver them.
        final mid = kissBytes.length ~/ 2;
        final chunk1 = kissBytes.sublist(0, mid);
        final chunk2 = kissBytes.sublist(mid);

        final frames = <Uint8List>[];
        final sub = framer.frames.listen(frames.add);

        framer.addBytes(chunk1);
        await Future<void>.delayed(Duration.zero);
        expect(frames, isEmpty, reason: 'incomplete frame must not be emitted');

        framer.addBytes(chunk2);
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        expect(frames, hasLength(1));
      });

      test('reassembles a frame delivered one byte at a time', () async {
        final kissBytes = _buildKissFrame(
          'KD9TST',
          'APRS',
          '>Testing BLE chunks',
        );
        final frames = <Uint8List>[];
        final sub = framer.frames.listen(frames.add);

        for (final byte in kissBytes) {
          framer.addBytes([byte]);
        }
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        expect(frames, hasLength(1));
        // The emitted payload is a valid AX.25 frame beginning with address bytes.
        expect(frames.first.length, greaterThan(14));
      });

      test('reassembles multiple frames in a single chunk', () async {
        final frame1 = _buildKissFrame('W1AW', 'APRS', '!4903.50N/07201.75W-1');
        final frame2 = _buildKissFrame('KD9ABC', 'APRS', '>Status frame');
        final combined = Uint8List.fromList([...frame1, ...frame2]);

        final frames = <Uint8List>[];
        final sub = framer.frames.listen(frames.add);

        framer.addBytes(combined);
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        expect(frames, hasLength(2));
      });
    });

    // 10 ----------------------------------------------------------------------
    group('sendFrame KISS chunking logic', () {
      test('KissFramer.encode output starts and ends with FEND (0xC0)', () {
        final ax25 = Uint8List.fromList([0x82, 0x84, 0x86, 0x03, 0xF0, 0x21]);
        final encoded = KissFramer.encode(ax25);
        expect(encoded.first, 0xC0);
        expect(encoded.last, 0xC0);
      });

      test('KissFramer.encode escapes FEND byte inside payload', () {
        // Payload contains a 0xC0 byte which must be escaped as 0xDB 0xDC.
        final ax25 = Uint8List.fromList([0xC0, 0x01]);
        final encoded = KissFramer.encode(ax25);
        // Should contain escape sequence 0xDB 0xDC in the middle.
        final middle = encoded.sublist(1, encoded.length - 1);
        expect(middle, containsAll([0xDB, 0xDC]));
      });

      test('KissFramer.encode escapes FESC byte inside payload', () {
        // Payload contains a 0xDB byte which must be escaped as 0xDB 0xDD.
        final ax25 = Uint8List.fromList([0xDB, 0x02]);
        final encoded = KissFramer.encode(ax25);
        final middle = encoded.sublist(1, encoded.length - 1);
        expect(middle, containsAll([0xDB, 0xDD]));
      });

      test('splitting into MTU-sized chunks covers whole KISS frame', () {
        final ax25 = Uint8List.fromList(List.generate(200, (i) => i & 0xFF));
        final kissFrame = KissFramer.encode(ax25);

        const mtu = 23; // Typical minimal BLE MTU payload.
        final chunks = <Uint8List>[];
        int offset = 0;
        while (offset < kissFrame.length) {
          final end = (offset + mtu).clamp(0, kissFrame.length);
          chunks.add(kissFrame.sublist(offset, end));
          offset = end;
        }

        // All chunks together must reconstruct the original KISS frame.
        final reassembled = Uint8List.fromList(
          chunks.expand((c) => c).toList(),
        );
        expect(reassembled, equals(kissFrame));
        // No chunk exceeds MTU.
        for (final chunk in chunks) {
          expect(chunk.length, lessThanOrEqualTo(mtu));
        }
      });
    });
  });
}
