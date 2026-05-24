import 'package:drift/drift.dart';

import '../../models/message_category.dart';
import '../../services/message_service.dart';
import 'conversations.dart';

/// Direct and group messages.
///
/// `id` uses the existing composite local-id format (`${peer}_${wireId}_${ms}`
/// for outgoing direct, `group_${name}_${ms}` for group, `${source}:${wireId}`
/// for incoming deduped) rather than a UUID — keeps the deduplication contract
/// stable across the migration.
@DataClassName('MessageEntryRow')
class MessageEntries extends Table {
  TextColumn get id => text()();
  TextColumn get conversationPeer => text()
      .named('conversation_peer')
      .references(Conversations, #peerCallsign, onDelete: KeyAction.cascade)();
  TextColumn get fromCallsign => text().named('from_callsign').nullable()();
  TextColumn get addressee => text().nullable()();
  TextColumn get body => text()();
  IntColumn get timestamp => integer()();
  BoolColumn get isOutgoing => boolean().named('is_outgoing')();
  TextColumn get wireId => text().named('wire_id').nullable()();
  TextColumn get status =>
      text().map(const EnumNameConverter(MessageStatus.values))();
  IntColumn get retryCount =>
      integer().named('retry_count').withDefault(const Constant(0))();
  TextColumn get category =>
      text().map(const EnumNameConverter(MessageCategory.values))();
  TextColumn get groupName => text().named('group_name').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
