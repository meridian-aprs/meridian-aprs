import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:meridian_aprs/core/packet/aprs_packet.dart' show PacketSource;
import 'package:meridian_aprs/database/meridian_database.dart';
import 'package:meridian_aprs/database/tables/packets.dart';

import '../helpers/test_database.dart';

void main() {
  late MeridianDatabase db;

  setUp(() => db = buildTestDatabase());
  tearDown(() => db.close());

  PacketsCompanion packet(
    String source, {
    int receivedAt = 1000,
    bool outgoing = false,
    PacketSource channel = PacketSource.aprsIs,
  }) => PacketsCompanion.insert(
    rawLine: '$source>APRS:!',
    packetType: PacketTypeTag.position,
    sourceCallsign: source,
    receivedAt: receivedAt,
    sourceChannel: channel,
    isOutgoing: Value(outgoing),
  );

  test('watchRecent returns newest-first and honours limit', () async {
    await db.packetDao.insertPacket(packet('A', receivedAt: 100));
    await db.packetDao.insertPacket(packet('B', receivedAt: 300));
    await db.packetDao.insertPacket(packet('C', receivedAt: 200));

    final rows = await db.packetDao.watchRecent(limit: 2).first;
    expect(rows.map((r) => r.sourceCallsign), ['B', 'C']);
  });

  test('isOutgoing + sourceChannel round-trip', () async {
    await db.packetDao.insertPacket(
      packet('A', outgoing: true, channel: PacketSource.serialTnc),
    );
    final row = (await db.packetDao.watchRecent().first).single;
    expect(row.isOutgoing, isTrue);
    expect(row.sourceChannel, PacketSource.serialTnc);
  });

  test('pruneOlderThan deletes packets before cutoff', () async {
    await db.packetDao.insertPacket(packet('OLD', receivedAt: 100));
    await db.packetDao.insertPacket(packet('NEW', receivedAt: 5000));

    final removed = await db.packetDao.pruneOlderThan(
      DateTime.fromMillisecondsSinceEpoch(1000),
    );
    expect(removed, 1);
    final rows = await db.packetDao.watchRecent().first;
    expect(rows.map((r) => r.sourceCallsign), ['NEW']);
  });

  test('clearAll empties the table', () async {
    await db.packetDao.insertPacket(packet('A'));
    await db.packetDao.clearAll();
    expect(await db.packetDao.watchRecent().first, isEmpty);
  });
}
