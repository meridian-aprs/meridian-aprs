import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_aprs/core/transport/aprs_transport.dart';
import 'package:meridian_aprs/core/transport/ble_constants.dart';
import 'package:meridian_aprs/core/transport/ble_diagnostics.dart';
import 'package:meridian_aprs/core/transport/ble_tnc_transport_impl.dart';
import 'package:meridian_aprs/core/transport/kiss_framer.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// A GATT service advertising the aprs-specs (Family A) KISS profile, so the
/// fake adapter lets a [BleTncTransport] reach [ConnectionStatus.connected].
BleGattService _aprsSpecsService() => BleGattService(
  kBleKissServiceUuid,
  const [kBleKissNotifyCharUuid, kBleKissWriteCharUuid],
);

/// A GATT service advertising the Benshi/BTECH (Family B) KISS profile.
BleGattService _benshiService() => BleGattService(
  kBenshiKissServiceUuid,
  const [kBenshiKissNotifyCharUuid, kBenshiKissWriteCharUuid],
);

// ---------------------------------------------------------------------------
// FakeBleDeviceAdapter
// ---------------------------------------------------------------------------

/// Fake [BleDeviceAdapter] for unit-testing [BleTncTransport].
///
/// The seam is fully plugin-agnostic, so this fake can now drive every path —
/// including the connected path (subscribe / notifications / writes) that
/// previously required the native stack.
class FakeBleDeviceAdapter implements BleDeviceAdapter {
  // ----- configuration knobs -----
  bool connectThrows = false;
  bool discoverThrows = false;
  bool pairThrows = false;
  bool paired = false;
  int fakeMtu = 512;
  List<BleGattService> services = [];

  // ----- call tracking -----
  int connectCallCount = 0;
  int disconnectCallCount = 0;
  int requestMtuCallCount = 0;
  int discoverCallCount = 0;
  int subscribeCallCount = 0;
  int isPairedCallCount = 0;
  int pairCallCount = 0;
  final List<Uint8List> writes = [];
  final List<bool> writeWithResponse = [];

  // ----- streams -----
  final _connStateController = StreamController<BleLinkState>.broadcast();
  final _notificationsController = StreamController<Uint8List>.broadcast();

  @override
  String deviceId = 'AA:BB:CC:DD:EE:FF';

  @override
  String displayName = 'FakeTNC';

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
    return fakeMtu;
  }

  @override
  Future<bool> isPaired() async {
    isPairedCallCount++;
    return paired;
  }

  @override
  Future<void> pair() async {
    pairCallCount++;
    if (pairThrows) throw Exception('FakeBleDeviceAdapter: pairing rejected');
    paired = true;
  }

  @override
  Future<List<BleGattService>> discoverServices() async {
    discoverCallCount++;
    if (discoverThrows) {
      throw Exception('FakeBleDeviceAdapter: discoverServices failed');
    }
    return services;
  }

  @override
  Future<void> subscribe(String serviceUuid, String charUuid) async {
    subscribeCallCount++;
  }

  @override
  Future<void> writeValue(
    String serviceUuid,
    String charUuid,
    Uint8List value, {
    required bool withResponse,
  }) async {
    writes.add(value);
    writeWithResponse.add(withResponse);
  }

  @override
  Stream<Uint8List> get notifications => _notificationsController.stream;

  @override
  Stream<BleLinkState> get connectionState => _connStateController.stream;

  /// Push a [BleLinkState] value onto the stream as if the platform reported a
  /// state change.
  void emitConnectionState(BleLinkState state) {
    _connStateController.add(state);
  }

  /// Push notify-characteristic bytes as if the peripheral sent them.
  void emitNotification(List<int> bytes) {
    _notificationsController.add(Uint8List.fromList(bytes));
  }

  Future<void> close() async {
    await _connStateController.close();
    await _notificationsController.close();
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BleTncTransport', () {
    late FakeBleDeviceAdapter fakeAdapter;
    late BleTncTransport transport;
    late BleDiagnostics savedDiag;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      // Swap the global diagnostics singleton for a per-test isolated instance
      // so assertions don't see leakage from other tests.
      savedDiag = BleDiagnostics.I;
      BleDiagnostics.I = BleDiagnostics(
        prefs: await SharedPreferences.getInstance(),
        persistDebounce: const Duration(milliseconds: 1),
      );
      // Production default is OFF so end-users don't pay for capture they
      // didn't ask for; transport tests need capture ON to assert
      // instrumentation actually fires.
      await BleDiagnostics.I.setEnabled(true);
      fakeAdapter = FakeBleDeviceAdapter();
      transport = BleTncTransport(
        'AA:BB:CC:DD:EE:FF',
        deviceName: 'FakeTNC',
        adapter: fakeAdapter,
      );
    });

    tearDown(() async {
      // Best-effort cleanup; transport may already be disconnected.
      try {
        await transport.disconnect();
      } catch (_) {}
      await fakeAdapter.close();
      BleDiagnostics.I = savedDiag;
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

    // 3a ----------------------------------------------------------------------
    test('connect() requests an MTU before discovering services', () async {
      await expectLater(transport.connect(), throwsA(isA<Exception>()));

      // universal_ble does not auto-negotiate inside connect(); the transport
      // must explicitly request the MTU to learn the usable payload size.
      expect(fakeAdapter.requestMtuCallCount, 1);
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
    test(
      'unexpected BLE disconnection while disconnected is ignored',
      () async {
        // No successful connect() yet → no conn-state listener registered → a
        // disconnected emission must be silently ignored and status unchanged.
        fakeAdapter.emitConnectionState(BleLinkState.disconnected);
        await Future<void>.delayed(Duration.zero);

        expect(transport.currentStatus, ConnectionStatus.disconnected);
      },
    );

    // 8 -----------------------------------------------------------------------
    test('sendFrame throws StateError when not connected', () async {
      final ax25 = Uint8List.fromList([0x01, 0x02, 0x03]);
      expect(() async => transport.sendFrame(ax25), throwsA(isA<StateError>()));
    });

    // 8a ----------------------------------------------------------------------
    test(
      'connect failure logs connectStart + connectFailed diagnostics',
      () async {
        fakeAdapter.connectThrows = true;

        await expectLater(transport.connect(), throwsA(isA<Exception>()));

        final kinds = BleDiagnostics.I.events.map((e) => e.kind).toList();
        expect(kinds, contains(BleEventKind.connectStart));
        expect(kinds, contains(BleEventKind.connectFailed));
      },
    );

    // 8b ----------------------------------------------------------------------
    test(
      'connect failure due to discoverServices logs serviceDiscoveryRetry',
      () async {
        fakeAdapter.discoverThrows = true;

        await expectLater(transport.connect(), throwsA(isA<Exception>()));

        final retries = BleDiagnostics.I.events
            .where((e) => e.kind == BleEventKind.serviceDiscoveryRetry)
            .toList();
        // The transport retries up to 3× before rethrowing.
        expect(retries, hasLength(3));
      },
    );

    // 8e ----------------------------------------------------------------------
    test('connection-state listener is torn down on connect failure', () async {
      // After a failed connect, the conn-state listener is also cancelled
      // (no live session for it to observe). Verify that a subsequent state
      // emission does NOT re-enter the disconnect handler — i.e. we don't
      // see disconnectUnexpected in the log.
      await expectLater(transport.connect(), throwsA(isA<Exception>()));
      BleDiagnostics.I.clear();

      fakeAdapter.emitConnectionState(BleLinkState.disconnected);
      await Future<void>.delayed(Duration.zero);

      final unexpected = BleDiagnostics.I.events
          .where((e) => e.kind == BleEventKind.disconnectUnexpected)
          .toList();
      expect(unexpected, isEmpty);
    });

    // 8f ----------------------------------------------------------------------
    test(
      'markInternalTeardown causes the next disconnect to log as internal',
      () async {
        // After a failed connect status is `error`, so disconnect() runs.
        fakeAdapter.connectThrows = true;
        await expectLater(transport.connect(), throwsA(isA<Exception>()));
        transport.markInternalTeardown();
        BleDiagnostics.I.clear();

        await transport.disconnect();

        final internal = BleDiagnostics.I.events
            .where((e) => e.kind == BleEventKind.disconnectInternal)
            .toList();
        final user = BleDiagnostics.I.events
            .where((e) => e.kind == BleEventKind.disconnectUser)
            .toList();
        expect(internal, hasLength(1));
        expect(user, isEmpty);
      },
    );

    // 8g ----------------------------------------------------------------------
    test(
      'disconnect without markInternalTeardown logs as user disconnect',
      () async {
        fakeAdapter.connectThrows = true;
        await expectLater(transport.connect(), throwsA(isA<Exception>()));
        BleDiagnostics.I.clear();

        await transport.disconnect();

        final internal = BleDiagnostics.I.events
            .where((e) => e.kind == BleEventKind.disconnectInternal)
            .toList();
        final user = BleDiagnostics.I.events
            .where((e) => e.kind == BleEventKind.disconnectUser)
            .toList();
        expect(internal, isEmpty);
        expect(user, hasLength(1));
      },
    );

    // 11 — connected path (now fully fakeable through the neutral seam) -------
    group('connected session', () {
      setUp(() {
        fakeAdapter.services = [_aprsSpecsService()];
      });

      test(
        'connect() reaches connected and subscribes to notify char',
        () async {
          await transport.connect();

          expect(transport.currentStatus, ConnectionStatus.connected);
          expect(transport.isConnected, isTrue);
          expect(transport.activeFamily, BleKissFamily.aprsSpecs);
          expect(fakeAdapter.subscribeCallCount, 1);
        },
      );

      test('negotiated MTU drives the chunk payload size', () async {
        fakeAdapter.fakeMtu = 23; // ATT default → 20-byte payload.
        await transport.connect();

        // A frame larger than one chunk must be split into withResponse writes.
        final ax25 = Uint8List.fromList(List.generate(80, (i) => i & 0xFF));
        await transport.sendFrame(ax25);

        expect(fakeAdapter.writes, isNotEmpty);
        expect(fakeAdapter.writes.length, greaterThan(1));
        for (final chunk in fakeAdapter.writes) {
          expect(chunk.length, lessThanOrEqualTo(20));
        }
        // sendFrame uses write-with-response for backpressure.
        expect(fakeAdapter.writeWithResponse, everyElement(isTrue));
      });

      test(
        'a notification reassembles into an APRS frame on frameStream',
        () async {
          await transport.connect();

          final frames = <Uint8List>[];
          final sub = transport.frameStream.listen(frames.add);

          final kiss = _buildKissFrame(
            'W1AW',
            'APRS',
            '!4903.50N/07201.75W-BLE',
          );
          fakeAdapter.emitNotification(kiss);
          await Future<void>.delayed(Duration.zero);
          await sub.cancel();

          expect(frames, hasLength(1));
        },
      );

      test(
        'unexpected disconnect after connect sets status to error',
        () async {
          await transport.connect();
          expect(transport.isConnected, isTrue);

          fakeAdapter.emitConnectionState(BleLinkState.disconnected);
          await Future<void>.delayed(Duration.zero);

          expect(transport.currentStatus, ConnectionStatus.error);
          final unexpected = BleDiagnostics.I.events
              .where((e) => e.kind == BleEventKind.disconnectUnexpected)
              .toList();
          expect(unexpected, hasLength(1));
        },
      );

      test('aprs-specs family never pairs', () async {
        // Family A uses unencrypted characteristics — bonding must not be
        // attempted (the previous plugin never prompted for it).
        fakeAdapter.paired = false;
        await transport.connect();

        expect(transport.isConnected, isTrue);
        expect(fakeAdapter.pairCallCount, 0);
        expect(fakeAdapter.isPairedCallCount, 0);
      });
    });

    // 12 — Benshi/BTECH (Family B) pairing -------------------------------------
    group('benshi family pairing', () {
      setUp(() {
        fakeAdapter.services = [_benshiService()];
      });

      test('pairs up-front when not yet bonded', () async {
        fakeAdapter.paired = false;
        await transport.connect();

        expect(transport.isConnected, isTrue);
        expect(fakeAdapter.pairCallCount, 1);
        final kinds = BleDiagnostics.I.events.map((e) => e.kind).toList();
        expect(kinds, contains(BleEventKind.pairingStarted));
        expect(kinds, contains(BleEventKind.pairingSucceeded));
      });

      test('skips pairing when already bonded', () async {
        fakeAdapter.paired = true;
        await transport.connect();

        expect(transport.isConnected, isTrue);
        expect(fakeAdapter.pairCallCount, 0);
      });

      test('pairing failure fails the connect with diagnostics', () async {
        fakeAdapter.paired = false;
        fakeAdapter.pairThrows = true;

        await expectLater(transport.connect(), throwsA(isA<Exception>()));

        expect(transport.currentStatus, ConnectionStatus.error);
        final kinds = BleDiagnostics.I.events.map((e) => e.kind).toList();
        expect(kinds, contains(BleEventKind.pairingFailed));
      });
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
