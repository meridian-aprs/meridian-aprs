import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meridian_aprs/core/packet/aprs_packet.dart';
import 'package:meridian_aprs/core/packet/station.dart';
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

      service.ingestLine('W1AW>APMDN0,TCPIP*:!4903.50N/07201.75W>Comment');
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

        service.ingestLine('W1AW>APMDN0,TCPIP*:!4903.50N/07201.75W>Comment');
        await Future<void>.delayed(Duration.zero);

        expect(stationMaps, hasLength(1));
        expect(service.currentStations, contains('W1AW'));
      },
    );

    test('adds to recentPackets with newest first', () async {
      service.ingestLine('W1AW>APMDN0:!4903.50N/07201.75W>A');
      service.ingestLine('W2XY>APMDN0:!3234.00N/08901.00W>B');
      await Future<void>.delayed(Duration.zero);

      expect(service.recentPackets, hasLength(2));
      expect(service.recentPackets.first.rawLine, contains('W2XY'));
    });

    test('stores packet source correctly', () async {
      final packets = <AprsPacket>[];
      service.packetStream.listen(packets.add);

      service.ingestLine(
        'W1AW>APMDN0:!4903.50N/07201.75W>TNC test',
        source: PacketSource.tnc,
      );
      await Future<void>.delayed(Duration.zero);

      expect(packets.first.transportSource, PacketSource.tnc);
    });
  });

  // ---------------------------------------------------------------------------
  // StationType classification
  // ---------------------------------------------------------------------------

  group('StationType classification', () {
    test('position packet with car symbol is classified as mobile', () async {
      service.ingestLine('W1AW>APMDN0,TCPIP*:!4903.50N/07201.75W>Car');
      await Future<void>.delayed(Duration.zero);
      expect(service.currentStations['W1AW']?.type, StationType.mobile);
    });

    test('position packet with house symbol is classified as fixed', () async {
      // Primary table '-' is a house/home
      service.ingestLine('W1AW>APMDN0,TCPIP*:!4903.50N/07201.75W-Fixed');
      await Future<void>.delayed(Duration.zero);
      expect(service.currentStations['W1AW']?.type, StationType.fixed);
    });

    test('position packet with wx symbol is classified as weather', () async {
      // Primary table '_' is a weather station
      service.ingestLine('W1AW>APMDN0,TCPIP*:!4903.50N/07201.75W_Weather');
      await Future<void>.delayed(Duration.zero);
      expect(service.currentStations['W1AW']?.type, StationType.weather);
    });
  });

  // ---------------------------------------------------------------------------
  // Object / Item packets
  // ---------------------------------------------------------------------------

  group('ObjectPacket handling', () {
    test('alive object adds a station keyed by object name', () async {
      service.ingestLine('W1ABC>APRS:;HOSPITAL *092345z4903.50N/07201.75W/');
      await Future<void>.delayed(Duration.zero);

      expect(service.currentStations, contains('HOSPITAL'));
      expect(service.currentStations['HOSPITAL']?.type, StationType.object);
    });

    test('killed object removes the station', () async {
      // Add the object first
      service.ingestLine('W1ABC>APRS:;HOSPITAL *092345z4903.50N/07201.75W/');
      await Future<void>.delayed(Duration.zero);
      expect(service.currentStations, contains('HOSPITAL'));

      // Then kill it
      service.ingestLine('W1ABC>APRS:;HOSPITAL _092345z4903.50N/07201.75W/');
      await Future<void>.delayed(Duration.zero);

      expect(service.currentStations, isNot(contains('HOSPITAL')));
    });
  });

  group('ItemPacket handling', () {
    test('alive item adds a station keyed by item name', () async {
      service.ingestLine('W1ABC>APRS:)RELAY !4903.50N/07201.75W-');
      await Future<void>.delayed(Duration.zero);

      expect(service.currentStations, contains('RELAY'));
      expect(service.currentStations['RELAY']?.type, StationType.object);
    });

    test('killed item removes the station', () async {
      service.ingestLine('W1ABC>APRS:)RELAY !4903.50N/07201.75W-');
      await Future<void>.delayed(Duration.zero);
      expect(service.currentStations, contains('RELAY'));

      service.ingestLine('W1ABC>APRS:)RELAY _4903.50N/07201.75W-');
      await Future<void>.delayed(Duration.zero);

      expect(service.currentStations, isNot(contains('RELAY')));
    });
  });

  // ---------------------------------------------------------------------------
  // Hidden type filter
  // ---------------------------------------------------------------------------

  group('hiddenTypes', () {
    test('initially empty — all types visible', () {
      expect(service.hiddenTypes, isEmpty);
    });

    test('setHiddenTypes updates hiddenTypes', () async {
      await service.setHiddenTypes({StationType.weather, StationType.mobile});
      expect(
        service.hiddenTypes,
        containsAll([StationType.weather, StationType.mobile]),
      );
    });

    test('setHiddenTypes persists to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final svc = StationService();
      await svc.loadPersistedHistory(prefs);

      await svc.setHiddenTypes({StationType.fixed});

      final stored = prefs.getStringList('station_hidden_types');
      expect(stored, contains('fixed'));
      await svc.stop();
    });

    test('loadPersistedHistory restores hiddenTypes', () async {
      SharedPreferences.setMockInitialValues({
        'station_hidden_types': ['weather', 'mobile'],
        'station_history_v1': '[]',
      });
      final prefs = await SharedPreferences.getInstance();
      final svc = StationService();
      await svc.loadPersistedHistory(prefs);

      expect(
        svc.hiddenTypes,
        containsAll([StationType.weather, StationType.mobile]),
      );
      await svc.stop();
    });

    test('hiddenTypes getter returns unmodifiable set', () async {
      await service.setHiddenTypes({StationType.fixed});
      final types = service.hiddenTypes;
      expect(() => types.add(StationType.other), throwsUnsupportedError);
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
            '[{"raw":"W1AW>APMDN0:>Test","src":"aprs_is","ts":$now}]',
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
        'packet_log_v1': '[{"raw":"W1AW>APMDN0:>Test","src":"tnc","ts":$now}]',
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
