import 'package:flutter_test/flutter_test.dart';

import 'package:meridian_aprs/database/meridian_database.dart';
import 'package:meridian_aprs/models/message_category.dart';
import 'package:meridian_aprs/models/message_status.dart';

import '../helpers/test_database.dart';

void main() {
  late MeridianDatabase db;

  setUp(() => db = buildTestDatabase());
  tearDown(() => db.close());

  Future<void> conv(String peer, {int lastMessageAt = 1000}) =>
      db.messageDao.upsertConversation(
        ConversationsCompanion.insert(
          peerCallsign: peer,
          lastMessageAt: lastMessageAt,
        ),
      );

  Future<void> entry(
    String id,
    String peer, {
    int timestamp = 1000,
    bool outgoing = false,
    MessageStatus status = MessageStatus.acked,
    MessageCategory category = MessageCategory.direct,
  }) => db.messageDao.insertEntry(
    MessageEntriesCompanion.insert(
      id: id,
      conversationPeer: peer,
      body: 'body',
      timestamp: timestamp,
      isOutgoing: outgoing,
      status: status,
      category: category,
    ),
  );

  test('unread increment + markRead', () async {
    await conv('KB1XYZ');
    await db.messageDao.incrementUnread('KB1XYZ');
    await db.messageDao.incrementUnread('KB1XYZ');
    var rows = await db.messageDao.getAllConversations();
    expect(rows.single.unreadCount, 2);

    await db.messageDao.markRead('KB1XYZ');
    rows = await db.messageDao.getAllConversations();
    expect(rows.single.unreadCount, 0);
  });

  test('insertEntry is idempotent on id (insertOrReplace)', () async {
    await conv('KB1XYZ');
    await entry('id1', 'KB1XYZ', status: MessageStatus.pending);
    await entry('id1', 'KB1XYZ', status: MessageStatus.acked);
    final rows = await db.messageDao.getEntriesForPeer('KB1XYZ');
    expect(rows, hasLength(1));
    expect(rows.single.status, MessageStatus.acked);
  });

  test('updateEntryStatus changes status + retryCount', () async {
    await conv('KB1XYZ');
    await entry('id1', 'KB1XYZ', status: MessageStatus.pending);
    await db.messageDao.updateEntryStatus(
      localId: 'id1',
      status: MessageStatus.retrying,
      retryCount: 3,
    );
    final row = (await db.messageDao.getEntriesForPeer('KB1XYZ')).single;
    expect(row.status, MessageStatus.retrying);
    expect(row.retryCount, 3);
  });

  test('getEntriesForPeer ordered ascending by timestamp', () async {
    await conv('KB1XYZ');
    await entry('b', 'KB1XYZ', timestamp: 300);
    await entry('a', 'KB1XYZ', timestamp: 100);
    final rows = await db.messageDao.getEntriesForPeer('KB1XYZ');
    expect(rows.map((r) => r.id), ['a', 'b']);
  });

  test('demoteInFlightToFailed only touches pending/retrying', () async {
    await conv('KB1XYZ');
    await entry('p', 'KB1XYZ', status: MessageStatus.pending);
    await entry('r', 'KB1XYZ', status: MessageStatus.retrying);
    await entry('a', 'KB1XYZ', status: MessageStatus.acked);
    await entry('c', 'KB1XYZ', status: MessageStatus.cancelled);

    final changed = await db.messageDao.demoteInFlightToFailed();
    expect(changed, 2);

    final byId = {
      for (final r in await db.messageDao.getEntriesForPeer('KB1XYZ'))
        r.id: r.status,
    };
    expect(byId['p'], MessageStatus.failed);
    expect(byId['r'], MessageStatus.failed);
    expect(byId['a'], MessageStatus.acked);
    expect(byId['c'], MessageStatus.cancelled);
  });

  test('pruneOlderThan removes aged entries from both tables', () async {
    await conv('KB1XYZ');
    await entry('old', 'KB1XYZ', timestamp: 100);
    await entry('new', 'KB1XYZ', timestamp: 5000);
    await db.messageDao.insertGroupEntry(
      GroupMessageEntriesCompanion.insert(
        id: 'g_old',
        groupName: 'WX',
        fromCallsign: 'K1ABC',
        body: 'b',
        timestamp: 100,
      ),
    );

    final removed = await db.messageDao.pruneOlderThan(
      DateTime.fromMillisecondsSinceEpoch(1000),
    );
    expect(removed, 2); // one direct + one group
    expect((await db.messageDao.getEntriesForPeer('KB1XYZ')).map((r) => r.id), [
      'new',
    ]);
    expect(await db.messageDao.watchGroupEntries('WX').first, isEmpty);
  });

  test('pruneEmptyConversations drops conversations with no entries', () async {
    await conv('EMPTY');
    await conv('HASMSG');
    await entry('id1', 'HASMSG');

    final removed = await db.messageDao.pruneEmptyConversations();
    expect(removed, 1);
    final peers = (await db.messageDao.getAllConversations()).map(
      (c) => c.peerCallsign,
    );
    expect(peers, ['HASMSG']);
  });

  test('cascade delete: removing conversation drops its entries', () async {
    await conv('KB1XYZ');
    await entry('id1', 'KB1XYZ');
    await db.messageDao.clearAll();
    expect(await db.messageDao.getEntriesForPeer('KB1XYZ'), isEmpty);
    expect(await db.messageDao.getAllConversations(), isEmpty);
  });

  test('group entries round-trip via group table', () async {
    await db.messageDao.insertGroupEntry(
      GroupMessageEntriesCompanion.insert(
        id: 'g1',
        groupName: 'WX',
        fromCallsign: 'K1ABC',
        body: 'storm',
        timestamp: 10,
      ),
    );
    final rows = await db.messageDao.watchGroupEntries('WX').first;
    expect(rows.single.body, 'storm');
  });
}
