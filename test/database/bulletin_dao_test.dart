import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:meridian_aprs/database/meridian_database.dart';
import 'package:meridian_aprs/models/bulletin.dart';

import '../helpers/test_database.dart';

void main() {
  late MeridianDatabase db;

  setUp(() => db = buildTestDatabase());
  tearDown(() => db.close());

  BulletinsCompanion incoming(
    String source,
    String addressee, {
    String body = 'body',
    int lastHeardAt = 1000,
    Set<BulletinTransport> transports = const {BulletinTransport.aprsIs},
  }) => BulletinsCompanion.insert(
    sourceCallsign: source,
    addressee: addressee,
    body: body,
    firstHeardAt: 1000,
    lastHeardAt: lastHeardAt,
    category: BulletinCategory.general,
    lineNumber: '0',
    transports: Value(transports),
  );

  test('upsertIncoming replaces on (source, addressee) conflict', () async {
    await db.bulletinDao.upsertIncoming(incoming('N0BBB', 'BLN0', body: 'v1'));
    await db.bulletinDao.upsertIncoming(incoming('N0BBB', 'BLN0', body: 'v2'));
    final rows = await db.bulletinDao.getAllIncoming();
    expect(rows, hasLength(1));
    expect(rows.single.body, 'v2');
  });

  test('transports converter round-trips a set', () async {
    await db.bulletinDao.upsertIncoming(
      incoming(
        'N0BBB',
        'BLN0',
        transports: {BulletinTransport.rf, BulletinTransport.aprsIs},
      ),
    );
    final row = (await db.bulletinDao.getAllIncoming()).single;
    expect(row.transports, {BulletinTransport.rf, BulletinTransport.aprsIs});
    expect(row.category, BulletinCategory.general);
  });

  test('getAllIncoming ordered by lastHeardAt descending', () async {
    await db.bulletinDao.upsertIncoming(
      incoming('A', 'BLN0', lastHeardAt: 100),
    );
    await db.bulletinDao.upsertIncoming(
      incoming('B', 'BLN1', lastHeardAt: 300),
    );
    final rows = await db.bulletinDao.getAllIncoming();
    expect(rows.map((r) => r.sourceCallsign), ['B', 'A']);
  });

  test('markIncomingRead + deleteIncoming target the right row', () async {
    await db.bulletinDao.upsertIncoming(incoming('N0BBB', 'BLN0'));
    await db.bulletinDao.markIncomingRead('N0BBB', 'BLN0');
    expect((await db.bulletinDao.getAllIncoming()).single.isRead, isTrue);

    await db.bulletinDao.deleteIncoming('N0BBB', 'BLN0');
    expect(await db.bulletinDao.getAllIncoming(), isEmpty);
  });

  test('pruneIncomingOlderThan deletes before cutoff', () async {
    await db.bulletinDao.upsertIncoming(
      incoming('OLD', 'BLN0', lastHeardAt: 100),
    );
    await db.bulletinDao.upsertIncoming(
      incoming('NEW', 'BLN1', lastHeardAt: 5000),
    );
    final removed = await db.bulletinDao.pruneIncomingOlderThan(
      DateTime.fromMillisecondsSinceEpoch(1000),
    );
    expect(removed, 1);
    expect(
      (await db.bulletinDao.getAllIncoming()).map((r) => r.sourceCallsign),
      ['NEW'],
    );
  });

  // --- Outgoing ------------------------------------------------------------

  Future<int> insertOutgoing({
    String addressee = 'BLN0',
    int intervalSeconds = 1800,
    int createdAt = 1000,
  }) => db.bulletinDao.insertOutgoing(
    OutgoingBulletinsCompanion.insert(
      addressee: addressee,
      body: 'b',
      intervalSeconds: intervalSeconds,
      createdAt: createdAt,
    ),
  );

  test('insertOutgoing assigns autoincrement ids', () async {
    final id1 = await insertOutgoing();
    final id2 = await insertOutgoing();
    expect(id2, greaterThan(id1));
    expect((await db.bulletinDao.getAllOutgoing()).length, 2);
  });

  test('recordOutgoingTransmission bumps count + stamps timestamp', () async {
    final id = await insertOutgoing();
    final ts = DateTime.fromMillisecondsSinceEpoch(4242);
    await db.bulletinDao.recordOutgoingTransmission(id, ts);
    await db.bulletinDao.recordOutgoingTransmission(id, ts);
    final row = (await db.bulletinDao.getAllOutgoing()).single;
    expect(row.transmissionCount, 2);
    expect(row.lastTransmittedAt, 4242);
  });

  test('updateOutgoingContent resets lastTransmittedAt + count', () async {
    final id = await insertOutgoing();
    await db.bulletinDao.recordOutgoingTransmission(
      id,
      DateTime.fromMillisecondsSinceEpoch(10),
    );
    await db.bulletinDao.updateOutgoingContent(id: id, body: 'new body');
    final row = (await db.bulletinDao.getAllOutgoing()).single;
    expect(row.body, 'new body');
    expect(row.transmissionCount, 0);
    expect(row.lastTransmittedAt, isNull);
  });

  test('updateOutgoingSchedule does NOT reset transmission state', () async {
    final id = await insertOutgoing();
    await db.bulletinDao.recordOutgoingTransmission(
      id,
      DateTime.fromMillisecondsSinceEpoch(10),
    );
    await db.bulletinDao.updateOutgoingSchedule(id: id, intervalSeconds: 3600);
    final row = (await db.bulletinDao.getAllOutgoing()).single;
    expect(row.intervalSeconds, 3600);
    expect(row.transmissionCount, 1);
    expect(row.lastTransmittedAt, 10);
  });

  test('setOutgoingEnabled + deleteOutgoing', () async {
    final id = await insertOutgoing();
    await db.bulletinDao.setOutgoingEnabled(id, false);
    expect((await db.bulletinDao.getAllOutgoing()).single.enabled, isFalse);

    await db.bulletinDao.deleteOutgoing(id);
    expect(await db.bulletinDao.getAllOutgoing(), isEmpty);
  });

  test('getAllOutgoing ordered by createdAt ascending', () async {
    await insertOutgoing(addressee: 'BLN1', createdAt: 300);
    await insertOutgoing(addressee: 'BLN0', createdAt: 100);
    final rows = await db.bulletinDao.getAllOutgoing();
    expect(rows.map((r) => r.addressee), ['BLN0', 'BLN1']);
  });
}
