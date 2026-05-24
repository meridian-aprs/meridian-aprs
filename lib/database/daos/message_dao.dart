import 'package:drift/drift.dart';

import '../../services/message_service.dart' show MessageStatus;
import '../meridian_database.dart';
import '../tables/conversations.dart';
import '../tables/group_message_entries.dart';
import '../tables/message_entries.dart';

part 'message_dao.g.dart';

@DriftAccessor(tables: [Conversations, MessageEntries, GroupMessageEntries])
class MessageDao extends DatabaseAccessor<MeridianDatabase>
    with _$MessageDaoMixin {
  MessageDao(super.db);

  // ---------------------------------------------------------------------------
  // Conversation upsert / unread tracking
  // ---------------------------------------------------------------------------

  Future<void> upsertConversation(ConversationsCompanion convo) =>
      into(conversations).insertOnConflictUpdate(convo);

  Future<int> incrementUnread(String peer) {
    return customUpdate(
      'UPDATE conversations '
      'SET unread_count = unread_count + 1 '
      'WHERE peer_callsign = ?',
      variables: [Variable<String>(peer)],
      updates: {conversations},
    );
  }

  Future<int> markRead(String peer) {
    return (update(conversations)..where((c) => c.peerCallsign.equals(peer)))
        .write(const ConversationsCompanion(unreadCount: Value(0)));
  }

  Stream<List<ConversationRow>> watchAllConversations() => (select(
    conversations,
  )..orderBy([(c) => OrderingTerm.desc(c.lastMessageAt)])).watch();

  // ---------------------------------------------------------------------------
  // Message entries (direct + group via category column)
  // ---------------------------------------------------------------------------

  Future<void> insertEntry(MessageEntriesCompanion entry) =>
      into(messageEntries).insert(entry, mode: InsertMode.insertOrReplace);

  Future<void> updateEntryStatus({
    required String localId,
    required MessageStatus status,
    int? retryCount,
  }) {
    return (update(messageEntries)..where((m) => m.id.equals(localId))).write(
      MessageEntriesCompanion(
        status: Value(status),
        retryCount: retryCount == null
            ? const Value.absent()
            : Value(retryCount),
      ),
    );
  }

  Stream<List<MessageEntryRow>> watchEntriesForPeer(String peer) {
    return (select(messageEntries)
          ..where((m) => m.conversationPeer.equals(peer))
          ..orderBy([(m) => OrderingTerm.asc(m.timestamp)]))
        .watch();
  }

  Future<List<MessageEntryRow>> getEntriesForPeer(String peer) {
    return (select(messageEntries)
          ..where((m) => m.conversationPeer.equals(peer))
          ..orderBy([(m) => OrderingTerm.asc(m.timestamp)]))
        .get();
  }

  /// Demote in-flight messages (pending/retrying) to failed on startup.
  /// Retry timers do not survive an app restart.
  Future<int> demoteInFlightToFailed() {
    return (update(messageEntries)..where(
          (m) =>
              m.status.equalsValue(MessageStatus.pending) |
              m.status.equalsValue(MessageStatus.retrying),
        ))
        .write(
          const MessageEntriesCompanion(status: Value(MessageStatus.failed)),
        );
  }

  // ---------------------------------------------------------------------------
  // Group messages (separate table)
  // ---------------------------------------------------------------------------

  Future<void> insertGroupEntry(GroupMessageEntriesCompanion entry) =>
      into(groupMessageEntries).insert(entry, mode: InsertMode.insertOrReplace);

  Stream<List<GroupMessageEntryRow>> watchGroupEntries(String groupName) {
    return (select(groupMessageEntries)
          ..where((g) => g.groupName.equals(groupName))
          ..orderBy([(g) => OrderingTerm.asc(g.timestamp)]))
        .watch();
  }

  /// Read all conversation rows (one-shot). Used by `loadHistory`.
  Future<List<ConversationRow>> getAllConversations() =>
      select(conversations).get();

  // ---------------------------------------------------------------------------
  // Retention pruning
  // ---------------------------------------------------------------------------

  /// Delete message + group-message rows older than [cutoff]. Returns the
  /// total number of rows removed across both tables.
  Future<int> pruneOlderThan(DateTime cutoff) async {
    final cutoffMs = cutoff.millisecondsSinceEpoch;
    final removedDirect = await (delete(
      messageEntries,
    )..where((m) => m.timestamp.isSmallerThanValue(cutoffMs))).go();
    final removedGroup = await (delete(
      groupMessageEntries,
    )..where((g) => g.timestamp.isSmallerThanValue(cutoffMs))).go();
    return removedDirect + removedGroup;
  }

  /// Drop conversation rows that no longer have any message entries — keeps
  /// the thread list free of empty "ghost" rows after a retention sweep.
  Future<int> pruneEmptyConversations() {
    return customUpdate(
      'DELETE FROM conversations WHERE peer_callsign NOT IN '
      '(SELECT DISTINCT conversation_peer FROM message_entries)',
      updates: {conversations},
      updateKind: UpdateKind.delete,
    );
  }

  Future<void> clearAll() async {
    await delete(messageEntries).go();
    await delete(groupMessageEntries).go();
    await delete(conversations).go();
  }
}
