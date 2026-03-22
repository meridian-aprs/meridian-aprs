import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_aprs/core/transport/kiss_tnc_transport.dart';
import 'package:meridian_aprs/core/transport/kiss_framer.dart';
import 'package:meridian_aprs/core/transport/serial_port_adapter.dart';
import 'package:meridian_aprs/core/transport/tnc_config.dart';
import 'package:meridian_aprs/core/transport/tnc_preset.dart';
import 'package:meridian_aprs/core/transport/transport_manager.dart';

// ---------------------------------------------------------------------------
// FakeKissTncTransport
// ---------------------------------------------------------------------------

/// Fully controllable [KissTncTransport] for [TransportManager] tests.
class FakeKissTncTransport implements KissTncTransport {
  final _frameController = StreamController<Uint8List>.broadcast();
  final _stateController = StreamController<ConnectionStatus>.broadcast();

  ConnectionStatus _status = ConnectionStatus.disconnected;
  bool disconnectCalled = false;

  bool connectThrows = false;

  @override
  Stream<Uint8List> get frameStream => _frameController.stream;

  @override
  Stream<ConnectionStatus> get connectionState => _stateController.stream;

  @override
  ConnectionStatus get currentStatus => _status;

  @override
  bool get isConnected => _status == ConnectionStatus.connected;

  @override
  Future<void> connect() async {
    _setStatus(ConnectionStatus.connecting);
    if (connectThrows) {
      _setStatus(ConnectionStatus.error);
      throw Exception('FakeKissTncTransport: connect failed');
    }
    _setStatus(ConnectionStatus.connected);
  }

  @override
  Future<void> disconnect() async {
    disconnectCalled = true;
    _setStatus(ConnectionStatus.disconnected);
  }

  @override
  Future<void> sendFrame(Uint8List ax25Frame) async {
    if (!isConnected) throw StateError('FakeKissTncTransport: not connected');
  }

  // --- test helpers ----------------------------------------------------------

  void simulateFrame(Uint8List frame) => _frameController.add(frame);

  void simulateUnexpectedDisconnect() {
    _setStatus(ConnectionStatus.error);
  }

  void _setStatus(ConnectionStatus s) {
    _status = s;
    _stateController.add(s);
  }

  Future<void> close() async {
    await _frameController.close();
    await _stateController.close();
  }
}

// ---------------------------------------------------------------------------
// FakeSerialPortAdapter (reused from serial_kiss_transport_test.dart)
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

  final writtenBytes = <Uint8List>[];

  @override
  void write(Uint8List data) => writtenBytes.add(data);

  @override
  void close() {
    closeCalled = true;
    if (!_byteController.isClosed) {
      _byteController.close();
    }
  }
}

// ---------------------------------------------------------------------------
// Helpers
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

Uint8List _buildRawAx25(String src, String dst, String aprsInfo) {
  final addr = <int>[..._encodeAddr(dst, 0), ..._encodeAddr(src, 0, last: true)];
  return Uint8List.fromList([...addr, 0x03, 0xF0, ...aprsInfo.codeUnits]);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('TransportManager', () {
    late TransportManager manager;

    setUp(() {
      manager = TransportManager();
    });

    tearDown(() async {
      // Disconnect first so the state stream does not receive events after
      // dispose() closes the controllers — TransportManager.dispose() calls
      // disconnect() unawaited, which can fire into a closed stream otherwise.
      try {
        await manager.disconnect();
      } catch (_) {}
      manager.dispose();
    });

    // 1 -----------------------------------------------------------------------
    test('initial state: no active transport, type is none, isConnected is false', () {
      expect(manager.activeTransport, isNull);
      expect(manager.activeType, TransportType.none);
      expect(manager.isConnected, isFalse);
      expect(manager.currentStatus, ConnectionStatus.disconnected);
    });

    // 2 -----------------------------------------------------------------------
    test('connectSerial with FakeSerialPortAdapter attaches transport and connects', () async {
      final fakeAdapter = FakeSerialPortAdapter();
      final config = TncConfig.fromPreset(TncPreset.mobilinkdTnc4, port: '/dev/ttyFAKE');

      await manager.connectSerial(config, adapter: fakeAdapter);

      expect(manager.activeType, TransportType.serial);
      expect(manager.isConnected, isTrue);
      expect(manager.currentStatus, ConnectionStatus.connected);
      expect(fakeAdapter.openCalled, isTrue);
    });

    // 3 -----------------------------------------------------------------------
    test('connectionState re-publishes events from the active transport', () async {
      final fakeAdapter = FakeSerialPortAdapter();
      final config = TncConfig.fromPreset(TncPreset.mobilinkdTnc4, port: '/dev/ttyFAKE');

      final capturedStates = <ConnectionStatus>[];
      final sub = manager.connectionState.listen(capturedStates.add);

      await manager.connectSerial(config, adapter: fakeAdapter);

      // Flush microtasks: the manager's _stateController is a broadcast stream
      // with async delivery (two hops: transport → manager → test), so events
      // may not arrive until after the current microtask queue is drained.
      await Future<void>.delayed(Duration.zero);

      await sub.cancel();

      expect(
        capturedStates,
        containsAll([ConnectionStatus.connecting, ConnectionStatus.connected]),
      );
    });

    // 4 -----------------------------------------------------------------------
    test('frameStream re-publishes frames from the active transport', () async {
      final fakeAdapter = FakeSerialPortAdapter();
      final config = TncConfig.fromPreset(TncPreset.mobilinkdTnc4, port: '/dev/ttyFAKE');

      await manager.connectSerial(config, adapter: fakeAdapter);

      final receivedFrames = <Uint8List>[];
      final sub = manager.frameStream.listen(receivedFrames.add);

      // Push a raw KISS frame through the fake serial adapter.
      final ax25 = _buildRawAx25('W1AW', 'APRS', '!4903.50N/07201.75W-Test');
      final kissFrame = KissFramer.encode(ax25);
      fakeAdapter._byteController.add(kissFrame);

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      await sub.cancel();

      expect(receivedFrames, isNotEmpty);
    });

    // 5 -----------------------------------------------------------------------
    test('disconnect() transitions to disconnected and sets type to none', () async {
      final fakeAdapter = FakeSerialPortAdapter();
      final config = TncConfig.fromPreset(TncPreset.mobilinkdTnc4, port: '/dev/ttyFAKE');
      await manager.connectSerial(config, adapter: fakeAdapter);

      final capturedStates = <ConnectionStatus>[];
      final sub = manager.connectionState.listen(capturedStates.add);

      await manager.disconnect();
      await Future<void>.delayed(Duration.zero);

      await sub.cancel();

      expect(manager.activeType, TransportType.none);
      expect(manager.isConnected, isFalse);
      expect(capturedStates, contains(ConnectionStatus.disconnected));
    });

    // 6 -----------------------------------------------------------------------
    test('disconnect() with no active transport does not throw', () async {
      await expectLater(manager.disconnect(), completes);
      expect(manager.activeType, TransportType.none);
    });

    // 7 -----------------------------------------------------------------------
    test('calling connectSerial twice disconnects previous transport first', () async {
      final fakeAdapter1 = FakeSerialPortAdapter();
      final fakeAdapter2 = FakeSerialPortAdapter();
      final config = TncConfig.fromPreset(TncPreset.mobilinkdTnc4, port: '/dev/ttyFAKE');

      await manager.connectSerial(config, adapter: fakeAdapter1);
      expect(fakeAdapter1.openCalled, isTrue);

      await manager.connectSerial(config, adapter: fakeAdapter2);

      // The first adapter should have been closed when replaced.
      expect(fakeAdapter1.closeCalled, isTrue);
      expect(fakeAdapter2.openCalled, isTrue);
      expect(manager.activeType, TransportType.serial);
      expect(manager.isConnected, isTrue);
    });

    // 8 -----------------------------------------------------------------------
    test('notifyListeners is called on state changes', () async {
      int notifyCount = 0;
      manager.addListener(() => notifyCount++);

      final fakeAdapter = FakeSerialPortAdapter();
      final config = TncConfig.fromPreset(TncPreset.mobilinkdTnc4, port: '/dev/ttyFAKE');
      await manager.connectSerial(config, adapter: fakeAdapter);
      await Future<void>.delayed(Duration.zero);

      expect(notifyCount, greaterThan(0));
    });

    // 9 -----------------------------------------------------------------------
    test('dispose closes internal stream controllers without error', () async {
      // A second manager to dispose explicitly.
      final m2 = TransportManager();
      expect(() => m2.dispose(), returnsNormally);
    });
  });
}
