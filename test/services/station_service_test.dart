import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meridian_aprs/core/connection/connection_registry.dart';
import 'package:meridian_aprs/core/packet/aprs_packet.dart';
import 'package:meridian_aprs/core/packet/station.dart';
import 'package:meridian_aprs/database/meridian_database.dart';
import 'package:meridian_aprs/services/station_service.dart';

import '../helpers/fake_meridian_connection.dart';
import '../helpers/test_database.dart';

void main() {
  late MeridianDatabase db;
  late StationService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = buildTestDatabase();
    service = StationService(
      stationDao: db.stationDao,
      packetDao: db.packetDao,
    );
  });

  tearDown(() async {
    await service.stop();
    await db.close();
  });

  // ---------------------------------------------------------------------------
  // ingestLine — basic decoding
  // ---------------------------------------------------------------------------

  group('ingestLine', () {
    test('emits decoded packet on packetStream', () async {
      final packets = <AprsPacket>[];
      service.packetStream.listen(packets.add);

      await service.ingestLine(
        'W1AW>APMDN0,TCPIP*:!4903.50N/07201.75W>Comment',
      );

      expect(packets, hasLength(1));
      expect(packets.first.rawLine, contains('W1AW'));
    });

    test('skips lines beginning with #', () async {
      final packets = <AprsPacket>[];
      service.packetStream.listen(packets.add);

      await service.ingestLine('# logresp W1AW unverified');

      expect(packets, isEmpty);
    });

    test('skips empty lines', () async {
      final packets = <AprsPacket>[];
      service.packetStream.listen(packets.add);

      await service.ingestLine('');

      expect(packets, isEmpty);
    });

    test(
      'position packet updates station map and emits stationUpdates',
      () async {
        final stationMaps = <Map<String, dynamic>>[];
        service.stationUpdates.listen((m) => stationMaps.add(m));

        await service.ingestLine(
          'W1AW>APMDN0,TCPIP*:!4903.50N/07201.75W>Comment',
        );

        expect(stationMaps, isNotEmpty);
        expect(service.currentStations, contains('W1AW'));
      },
    );

    test('adds to recentPackets with newest first', () async {
      await service.ingestLine('W1AW>APMDN0:!4903.50N/07201.75W>A');
      await service.ingestLine('W2XY>APMDN0:!3234.00N/08901.00W>B');

      expect(service.recentPackets, hasLength(2));
      expect(service.recentPackets.first.rawLine, contains('W2XY'));
    });

    test('stores packet source correctly', () async {
      final packets = <AprsPacket>[];
      service.packetStream.listen(packets.add);

      await service.ingestLine(
        'W1AW>APMDN0:!4903.50N/07201.75W>TNC test',
        source: PacketSource.tnc,
      );

      expect(packets.first.transportSource, PacketSource.tnc);
    });
  });

  // ---------------------------------------------------------------------------
  // StationType classification
  // ---------------------------------------------------------------------------

  group('StationType classification', () {
    test('position packet with car symbol is classified as mobile', () async {
      await service.ingestLine('W1AW>APMDN0,TCPIP*:!4903.50N/07201.75W>Car');
      expect(service.currentStations['W1AW']?.type, StationType.mobile);
    });

    test('position packet with house symbol is classified as fixed', () async {
      await service.ingestLine('W1AW>APMDN0,TCPIP*:!4903.50N/07201.75W-Fixed');
      expect(service.currentStations['W1AW']?.type, StationType.fixed);
    });

    test('position packet with wx symbol is classified as weather', () async {
      await service.ingestLine(
        'W1AW>APMDN0,TCPIP*:!4903.50N/07201.75W_Weather',
      );
      expect(service.currentStations['W1AW']?.type, StationType.weather);
    });
  });

  // ---------------------------------------------------------------------------
  // MessageCapability derivation
  // ---------------------------------------------------------------------------

  group('MessageCapability', () {
    test('position with `!` DTI is unsupported', () async {
      await service.ingestLine('W1AW>APMDN0,TCPIP*:!4903.50N/07201.75W>NoMsg');
      expect(
        service.currentStations['W1AW']?.messageCapability,
        MessageCapability.unsupported,
      );
    });

    test('position with `=` DTI is supported', () async {
      await service.ingestLine(
        'W1AW>APMDN0,TCPIP*:=4903.50N/07201.75W>WithMsg',
      );
      expect(
        service.currentStations['W1AW']?.messageCapability,
        MessageCapability.supported,
      );
    });

    test('object packet defaults to unknown', () async {
      await service.ingestLine(
        'W1ABC>APRS:;HOSPITAL *092345z4903.50N/07201.75W/',
      );
      expect(
        service.currentStations['HOSPITAL']?.messageCapability,
        MessageCapability.unknown,
      );
    });

    test('two consecutive supported positions retain supported', () async {
      await service.ingestLine('W1AW>APMDN0,TCPIP*:=4903.50N/07201.75W>First');
      await service.ingestLine('W1AW>APMDN0,TCPIP*:=4903.50N/07201.75W>Second');
      expect(
        service.currentStations['W1AW']?.messageCapability,
        MessageCapability.supported,
      );
    });

    test(
      'later position packet overrides prior capability (unsupported→supported)',
      () async {
        await service.ingestLine(
          'W1AW>APMDN0,TCPIP*:!4903.50N/07201.75W>NoMsg',
        );
        await service.ingestLine(
          'W1AW>APMDN0,TCPIP*:=4903.50N/07201.75W>WithMsg',
        );
        expect(
          service.currentStations['W1AW']?.messageCapability,
          MessageCapability.supported,
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Object / Item packets
  // ---------------------------------------------------------------------------

  group('ObjectPacket handling', () {
    test('alive object adds a station keyed by object name', () async {
      await service.ingestLine(
        'W1ABC>APRS:;HOSPITAL *092345z4903.50N/07201.75W/',
      );

      expect(service.currentStations, contains('HOSPITAL'));
      expect(service.currentStations['HOSPITAL']?.type, StationType.object);
    });

    test('killed object removes the station', () async {
      await service.ingestLine(
        'W1ABC>APRS:;HOSPITAL *092345z4903.50N/07201.75W/',
      );
      expect(service.currentStations, contains('HOSPITAL'));

      await service.ingestLine(
        'W1ABC>APRS:;HOSPITAL _092345z4903.50N/07201.75W/',
      );

      expect(service.currentStations, isNot(contains('HOSPITAL')));
    });
  });

  group('ItemPacket handling', () {
    test('alive item adds a station keyed by item name', () async {
      await service.ingestLine('W1ABC>APRS:)RELAY !4903.50N/07201.75W-');

      expect(service.currentStations, contains('RELAY'));
      expect(service.currentStations['RELAY']?.type, StationType.object);
    });

    test('killed item removes the station', () async {
      await service.ingestLine('W1ABC>APRS:)RELAY !4903.50N/07201.75W-');
      expect(service.currentStations, contains('RELAY'));

      await service.ingestLine('W1ABC>APRS:)RELAY _4903.50N/07201.75W-');

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
      final localDb = buildTestDatabase();
      final svc = StationService(
        stationDao: localDb.stationDao,
        packetDao: localDb.packetDao,
      );
      await svc.loadPersistedSettings(prefs);

      await svc.setHiddenTypes({StationType.fixed});

      final stored = prefs.getStringList('station_hidden_types');
      expect(stored, contains('fixed'));
      await svc.stop();
      await localDb.close();
    });

    test('loadPersistedSettings restores hiddenTypes', () async {
      SharedPreferences.setMockInitialValues({
        'station_hidden_types': ['weather', 'mobile'],
      });
      final prefs = await SharedPreferences.getInstance();
      final localDb = buildTestDatabase();
      final svc = StationService(
        stationDao: localDb.stationDao,
        packetDao: localDb.packetDao,
      );
      await svc.loadPersistedSettings(prefs);

      expect(
        svc.hiddenTypes,
        containsAll([StationType.weather, StationType.mobile]),
      );
      await svc.stop();
      await localDb.close();
    });

    test('hiddenTypes getter returns unmodifiable set', () async {
      await service.setHiddenTypes({StationType.fixed});
      final types = service.hiddenTypes;
      expect(() => types.add(StationType.other), throwsUnsupportedError);
    });
  });

  // ---------------------------------------------------------------------------
  // Drift persistence (ADR-062) — what was previously the
  // `loadPersistedHistory` group is replaced by these tests.
  // ---------------------------------------------------------------------------

  group('drift persistence', () {
    test('ingested packets survive service restart with the same DB', () async {
      await service.ingestLine('W1AW>APMDN0:!4903.50N/07201.75W>Hello');
      await service.stop();

      final svc2 = StationService(
        stationDao: db.stationDao,
        packetDao: db.packetDao,
      );
      // The watch-stream cache hydrates on first emission; await one stream
      // tick so the snapshot is populated before reading.
      await svc2.stationUpdates.first;

      expect(svc2.currentStations, contains('W1AW'));
      await svc2.stop();
    });

    test('clearPacketLog wipes underlying drift rows', () async {
      await service.ingestLine('W1AW>APMDN0:!4903.50N/07201.75W>Hello');
      expect(service.recentPackets, hasLength(1));

      await service.clearPacketLog();

      expect(service.recentPackets, isEmpty);
      final rows = await db.packetDao.watchRecent(limit: 10).first;
      expect(rows, isEmpty);
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
  // attach — single subscription against ConnectionRegistry.lines
  // ---------------------------------------------------------------------------

  group('attach', () {
    late ConnectionRegistry registry;
    late FakeMeridianConnection aprsIs;
    late FakeMeridianConnection bleTnc;
    late FakeMeridianConnection serial;

    setUp(() {
      registry = ConnectionRegistry();
      aprsIs = FakeMeridianConnection(
        id: 'aprs_is',
        displayName: 'APRS-IS',
        type: ConnectionType.aprsIs,
      );
      bleTnc = FakeMeridianConnection(
        id: 'ble_tnc',
        displayName: 'BLE TNC',
        type: ConnectionType.bleTnc,
      );
      serial = FakeMeridianConnection(
        id: 'serial_tnc',
        displayName: 'Serial TNC',
        type: ConnectionType.serialTnc,
      );
      registry.register(aprsIs);
      registry.register(bleTnc);
      registry.register(serial);
    });

    tearDown(() async {
      await aprsIs.dispose();
      await bleTnc.dispose();
      await serial.dispose();
      registry.dispose();
    });

    test('routes lines from each connection with the correct source', () async {
      final packets = <AprsPacket>[];
      service.packetStream.listen(packets.add);

      service.attach(registry);

      aprsIs.simulateLine('W1AW>APMDN0,TCPIP*:!4903.50N/07201.75W>via IS');
      bleTnc.simulateLine('W2BLE>APMDN0:!4903.50N/07201.75W>via BLE');
      serial.simulateLine('W3SER>APMDN0:!4903.50N/07201.75W>via Serial');
      // Allow ingest chain to drain.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(packets, hasLength(3));
      expect(
        packets.map((p) => p.transportSource),
        containsAll(<PacketSource>[
          PacketSource.aprsIs,
          PacketSource.bleTnc,
          PacketSource.serialTnc,
        ]),
      );
      final byCallsign = {
        for (final p in packets) p.rawLine.split('>').first: p.transportSource,
      };
      expect(byCallsign['W1AW'], PacketSource.aprsIs);
      expect(byCallsign['W2BLE'], PacketSource.bleTnc);
      expect(byCallsign['W3SER'], PacketSource.serialTnc);
    });

    test('stop() cancels the registry subscription', () async {
      service.attach(registry);
      await service.stop();

      expect(
        () => aprsIs.simulateLine(
          'W1AW>APMDN0,TCPIP*:!4903.50N/07201.75W>after stop',
        ),
        returnsNormally,
      );
    });

    test('calling attach twice throws in debug builds', () {
      service.attach(registry);
      expect(() => service.attach(registry), throwsA(isA<AssertionError>()));
    });
  });
}
