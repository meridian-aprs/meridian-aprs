import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meridian_aprs/core/packet/aprs_packet.dart';
import 'package:meridian_aprs/core/packet/aprs_parser.dart';
import 'package:meridian_aprs/core/transport/aprs_transport.dart';
import 'package:meridian_aprs/core/transport/kiss_framer.dart';
import 'package:meridian_aprs/core/transport/serial_port_adapter.dart';
import 'package:meridian_aprs/core/transport/tnc_config.dart';
import 'package:meridian_aprs/core/transport/tnc_preset.dart';
import 'package:meridian_aprs/services/station_service.dart';
import 'package:meridian_aprs/services/tnc_service.dart';

// ---------------------------------------------------------------------------
// FakeSerialPortAdapter
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
  void write(Uint8List data) {}

  @override
  void close() {
    closeCalled = true;
    if (!_byteController.isClosed) {
      _byteController.close();
    }
  }

  void pushBytes(List<int> bytes) {
    if (!_byteController.isClosed) {
      _byteController.add(Uint8List.fromList(bytes));
    }
  }
}

// ---------------------------------------------------------------------------
// FakeAprsTransport (stub for constructing StationService)
// ---------------------------------------------------------------------------

class FakeAprsTransport implements AprsTransport {
  final _lines = StreamController<String>.broadcast();
  final _state = StreamController<ConnectionStatus>.broadcast();

  @override
  Stream<String> get lines => _lines.stream;

  @override
  Stream<ConnectionStatus> get connectionState => _state.stream;

  @override
  ConnectionStatus get currentStatus => ConnectionStatus.disconnected;

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  void sendLine(String line) {}
}

// ---------------------------------------------------------------------------
// AX.25 / KISS frame builder
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
// Tests
// ---------------------------------------------------------------------------

void main() {
  final parser = AprsParser();

  group('TncService', () {
    late FakeAprsTransport fakeAprsTransport;
    late StationService stationService;
    late TncService tncService;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      fakeAprsTransport = FakeAprsTransport();
      stationService = StationService(fakeAprsTransport);
      tncService = TncService(stationService);
    });

    tearDown(() async {
      // Disconnect before dispose to avoid the async race in
      // TransportManager.dispose() where disconnect() is called unawaited
      // after the stream controllers are closed.
      await tncService.disconnect();
      tncService.dispose();
    });

    // 1 -----------------------------------------------------------------------
    test('initial state: status disconnected, activeTransportType is none', () {
      expect(tncService.currentStatus, ConnectionStatus.disconnected);
      expect(tncService.activeTransportType, TransportType.none);
    });

    // 2 -----------------------------------------------------------------------
    test('connect via transportManager transitions to connected', () async {
      final fakeAdapter = FakeSerialPortAdapter();
      final config = TncConfig.fromPreset(TncPreset.mobilinkdTnc4, port: '/dev/ttyFAKE');

      // TncService.connect() calls _transportManager.connectSerial() without
      // adapter injection. We drive via the exposed transportManager instead.
      await tncService.transportManager.connectSerial(config, adapter: fakeAdapter);

      expect(tncService.currentStatus, ConnectionStatus.connected);
      expect(tncService.activeTransportType, TransportType.serial);
      expect(fakeAdapter.openCalled, isTrue);
    });

    // 3 -----------------------------------------------------------------------
    test(
      'StationService.ingestLine forwards parsed packet to packetStream',
      () async {
        // Verifies the service layer that TncService delegates to:
        // ingestLine() → AprsParser → packetStream.
        final packets = <AprsPacket>[];
        final sub = stationService.packetStream.listen(packets.add);

        const aprsInfo = '!4903.50N/07201.75W-TNC test';
        stationService.ingestLine('W1AW>APRS:$aprsInfo');
        await Future<void>.delayed(Duration.zero);

        await sub.cancel();

        expect(packets, hasLength(1));
        expect(packets.first.source, 'W1AW');
        expect(packets.first, isA<PositionPacket>());
      },
    );

    // 4 -----------------------------------------------------------------------
    test(
      'full pipeline: KISS bytes from serial adapter reach packetStream',
      () async {
        final fakeAdapter = FakeSerialPortAdapter();
        final config = TncConfig.fromPreset(TncPreset.mobilinkdTnc4, port: '/dev/ttyFAKE');

        // Subscribe to packetStream before connecting.
        final packets = <AprsPacket>[];
        final sub = stationService.packetStream.listen(packets.add);

        // Connect transport.
        await tncService.transportManager.connectSerial(config, adapter: fakeAdapter);

        // Wire the frame bridge manually — replicates TncService._onFrame.
        // (TncService._attachBridge is called only by tncService.connect(),
        // which bypasses adapter injection. We drive the manager directly and
        // replicate the bridge logic here to observe the full pipeline.)
        final bridgeSub = tncService.transportManager.frameStream.listen(
          (frameBytes) {
            final packet = parser.parseFrame(frameBytes);
            if (packet.rawLine.isNotEmpty) {
              stationService.ingestLine(packet.rawLine);
            }
          },
        );

        const aprsInfo = '!4903.50N/07201.75W-Bridge test';
        final kissBytes = _buildKissFrame('KD9TST', 'APRS', aprsInfo);

        fakeAdapter.pushBytes(kissBytes);

        // Allow the async pipeline to flush (serial bytes → KissFramer →
        // TransportManager.frameStream → bridge listener → ingestLine →
        // packetStream).
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        await bridgeSub.cancel();
        await sub.cancel();

        expect(packets, isNotEmpty);
        expect(packets.first.source, 'KD9TST');
      },
    );

    // 5 -----------------------------------------------------------------------
    test('empty ingestLine is silently skipped — no packet emitted', () async {
      final packets = <AprsPacket>[];
      final sub = stationService.packetStream.listen(packets.add);

      stationService.ingestLine('');
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(packets, isEmpty);
    });

    // 6 -----------------------------------------------------------------------
    test('comment lines (#) are silently skipped', () async {
      final packets = <AprsPacket>[];
      final sub = stationService.packetStream.listen(packets.add);

      stationService.ingestLine('# aprsd 3.0.0 build ...');
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(packets, isEmpty);
    });

    // 7 -----------------------------------------------------------------------
    test('disconnect() transitions status to disconnected and type to none', () async {
      final fakeAdapter = FakeSerialPortAdapter();
      final config = TncConfig.fromPreset(TncPreset.mobilinkdTnc4, port: '/dev/ttyFAKE');

      await tncService.transportManager.connectSerial(config, adapter: fakeAdapter);
      expect(tncService.currentStatus, ConnectionStatus.connected);

      await tncService.disconnect();

      expect(tncService.currentStatus, ConnectionStatus.disconnected);
      expect(tncService.activeTransportType, TransportType.none);
    });

    // 8 -----------------------------------------------------------------------
    test('lastErrorMessage is null before any connection attempt', () {
      expect(tncService.lastErrorMessage, isNull);
    });

    // 9 -----------------------------------------------------------------------
    test('activeConfig is null before any connect call', () {
      expect(tncService.activeConfig, isNull);
    });
  });
}
