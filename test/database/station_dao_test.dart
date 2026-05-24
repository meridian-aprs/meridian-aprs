import 'package:flutter_test/flutter_test.dart';

import 'package:meridian_aprs/core/packet/station.dart';
import 'package:meridian_aprs/database/meridian_database.dart';

import '../helpers/test_database.dart';

void main() {
  late MeridianDatabase db;

  setUp(() => db = buildTestDatabase());
  tearDown(() => db.close());

  StationsCompanion station(
    String callsign, {
    int lastHeard = 1000,
    double lat = 1.0,
    double lon = 2.0,
    StationType type = StationType.fixed,
  }) => StationsCompanion.insert(
    callsign: callsign,
    symbolTable: '/',
    symbolCode: '>',
    comment: '',
    rawPacket: '$callsign>APRS:!',
    lastHeard: lastHeard,
    stationType: type,
    messageCapability: MessageCapability.unknown,
    lat: lat,
    lon: lon,
  );

  test('upsertStation inserts then updates on conflict', () async {
    await db.stationDao.upsertStation(station('W1AW', lat: 1));
    await db.stationDao.upsertStation(station('W1AW', lat: 9));

    final all = await db.stationDao.getAllStations();
    expect(all, hasLength(1));
    expect(all.single.lat, 9);
  });

  test('enum columns round-trip', () async {
    await db.stationDao.upsertStation(
      station('W1AW', type: StationType.weather),
    );
    final row = await db.stationDao.getStation('W1AW');
    expect(row!.stationType, StationType.weather);
    expect(row.messageCapability, MessageCapability.unknown);
  });

  test('getPositionHistory returns entries oldest-first', () async {
    await db.stationDao.upsertStation(station('W1AW'));
    await db.stationDao.appendPositionHistory(
      PositionHistoryCompanion.insert(
        callsign: 'W1AW',
        latitude: 1,
        longitude: 1,
        timestamp: 300,
      ),
    );
    await db.stationDao.appendPositionHistory(
      PositionHistoryCompanion.insert(
        callsign: 'W1AW',
        latitude: 2,
        longitude: 2,
        timestamp: 100,
      ),
    );
    final history = await db.stationDao.getPositionHistory('W1AW');
    expect(history.map((h) => h.timestamp), [100, 300]);
  });

  test(
    'upsertWithPositionHistory appends previous + caps per station',
    () async {
      await db.stationDao.upsertStation(station('W1AW'));
      // Append 5 history rows then upsert with cap of 3.
      for (var i = 0; i < 5; i++) {
        await db.stationDao.appendPositionHistory(
          PositionHistoryCompanion.insert(
            callsign: 'W1AW',
            latitude: i.toDouble(),
            longitude: 0,
            timestamp: i,
          ),
        );
      }
      await db.stationDao.upsertWithPositionHistory(
        station: station('W1AW', lat: 50),
        previousPosition: PositionHistoryCompanion.insert(
          callsign: 'W1AW',
          latitude: 99,
          longitude: 0,
          timestamp: 99,
        ),
        capHistoryAt: 3,
      );

      final history = await db.stationDao.getPositionHistory('W1AW');
      expect(history, hasLength(3));
      // Newest three by timestamp survive: 3, 4, 99.
      expect(history.map((h) => h.timestamp), [3, 4, 99]);
    },
  );

  test('deleteByCallsign cascades position history', () async {
    await db.stationDao.upsertStation(station('W1AW'));
    await db.stationDao.appendPositionHistory(
      PositionHistoryCompanion.insert(
        callsign: 'W1AW',
        latitude: 1,
        longitude: 1,
        timestamp: 1,
      ),
    );
    await db.stationDao.deleteByCallsign('W1AW');

    expect(await db.stationDao.getStation('W1AW'), isNull);
    expect(await db.stationDao.getPositionHistory('W1AW'), isEmpty);
  });

  test('pruneOlderThan removes stations before cutoff and cascades', () async {
    await db.stationDao.upsertStation(station('OLD', lastHeard: 100));
    await db.stationDao.appendPositionHistory(
      PositionHistoryCompanion.insert(
        callsign: 'OLD',
        latitude: 1,
        longitude: 1,
        timestamp: 100,
      ),
    );
    await db.stationDao.upsertStation(station('NEW', lastHeard: 5000));

    final removed = await db.stationDao.pruneOlderThan(
      DateTime.fromMillisecondsSinceEpoch(1000),
    );
    expect(removed, 1);
    expect(await db.stationDao.getStation('OLD'), isNull);
    expect(await db.stationDao.getPositionHistory('OLD'), isEmpty);
    expect(await db.stationDao.getStation('NEW'), isNotNull);
  });

  test('watchAllStations emits on insert', () async {
    final first = db.stationDao.watchAllStations().firstWhere(
      (rows) => rows.isNotEmpty,
    );
    await db.stationDao.upsertStation(station('W1AW'));
    expect(await first, hasLength(1));
  });

  test('clearAll empties both tables', () async {
    await db.stationDao.upsertStation(station('W1AW'));
    await db.stationDao.appendPositionHistory(
      PositionHistoryCompanion.insert(
        callsign: 'W1AW',
        latitude: 1,
        longitude: 1,
        timestamp: 1,
      ),
    );
    await db.stationDao.clearAll();
    expect(await db.stationDao.getAllStations(), isEmpty);
    expect(await db.stationDao.getAllPositionHistory(), isEmpty);
  });
}
