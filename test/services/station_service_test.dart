import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meridian_aprs/core/packet/aprs_packet.dart';
import 'package:meridian_aprs/services/station_service.dart';

void main() {
  late StationService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = StationService();
  });

  tearDown(() async {
    await service.stop();
  });

  // ---------------------------------------------------------------------------
  // ingestLine — basic decoding
  // ---------------------------------------------------------------------------

  group('ingestLine', () {
    test('emits decoded packet on packetStream', () async {
      final packets = <AprsPacket>[];
      service.packetStream.listen(packets.add);

      service.ingestLine('W1AW>APZMDN,TCPIP*:!4903.50N/07201.75W>Comment');
      await Future<void>.delayed(Duration.zero);

      expect(packets, hasLength(1));
      expect(packets.first.rawLine, contains('W1AW'));
    });

    test('skips lines beginning with #', () async {
      final packets = <AprsPacket>[];
      service.packetStream.listen(packets.add);

      service.ingestLine('# logresp W1AW unverified');
      await Future<void>.delayed(Duration.zero);

      expect(packets, isEmpty);
    });

    test('skips empty lines', () async {
      final packets = <AprsPacket>[];
      service.packetStream.listen(packets.add);

      service.ingestLine('');
      await Future<void>.delayed(Duration.zero);

      expect(packets, isEmpty);
    });

    test(
      'position packet updates station map and emits stationUpdates',
      () async {
        final stationMaps = <Map<String, dynamic>>[];
        service.stationUpdates.listen((m) => stationMaps.add(m));

        service.ingestLine('W1AW>APZMDN,TCPIP*:!4903.50N/07201.75W>Comment');
        await Future<void>.delayed(Duration.zero);

        expect(stationMaps, hasLength(1));
        expect(service.currentStations, contains('W1AW'));
      },
    );

    test('adds to recentPackets with newest first', () async {
      service.ingestLine('W1AW>APZMDN:!4903.50N/07201.75W>A');
      service.ingestLine('W2XY>APZMDN:!3234.00N/08901.00W>B');
      await Future<void>.delayed(Duration.zero);

      expect(service.recentPackets, hasLength(2));
      expect(service.recentPackets.first.rawLine, contains('W2XY'));
    });

    test('stores packet source correctly', () async {
      final packets = <AprsPacket>[];
      service.packetStream.listen(packets.add);

      service.ingestLine(
        'W1AW>APZMDN:!4903.50N/07201.75W>TNC test',
        source: PacketSource.tnc,
      );
      await Future<void>.delayed(Duration.zero);

      expect(packets.first.transportSource, PacketSource.tnc);
    });
  });

  // ---------------------------------------------------------------------------
  // backward-compat stubs
  // ---------------------------------------------------------------------------

  group('backward-compat stubs', () {
    test('currentConnectionStatus returns disconnected', () {
      expect(
        service.currentConnectionStatus.toString(),
        contains('disconnected'),
      );
    });

    test('start() completes without throwing', () async {
      await expectLater(service.start(), completes);
    });

    test('connectAprsIs() is a no-op', () async {
      await expectLater(service.connectAprsIs(), completes);
    });

    test('disconnectAprsIs() is a no-op', () async {
      await expectLater(service.disconnectAprsIs(), completes);
    });
  });

  // ---------------------------------------------------------------------------
  // history persistence
  // ---------------------------------------------------------------------------

  group('loadPersistedHistory', () {
    test('restores packets from shared preferences', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'packet_log_v1':
            '[{"raw":"W1AW>APZMDN:>Test","src":"aprs_is","ts":$now}]',
        'station_history_v1': '[]',
      });
      final prefs = await SharedPreferences.getInstance();
      final svc = StationService();
      await svc.loadPersistedHistory(prefs);

      expect(svc.recentPackets, hasLength(1));
      await svc.stop();
    });

    test('maps legacy "tnc" source to PacketSource.tnc', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'packet_log_v1': '[{"raw":"W1AW>APZMDN:>Test","src":"tnc","ts":$now}]',
        'station_history_v1': '[]',
      });
      final prefs = await SharedPreferences.getInstance();
      final svc = StationService();
      await svc.loadPersistedHistory(prefs);

      expect(svc.recentPackets.first.transportSource, PacketSource.tnc);
      await svc.stop();
    });
  });
}
