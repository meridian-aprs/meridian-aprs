import 'package:drift/drift.dart';

/// One row per direct or group thread. Direct threads are keyed by base
/// callsign (uppercased, no SSID); group threads are keyed `#GROUP:<NAME>`.
@DataClassName('ConversationRow')
class Conversations extends Table {
  TextColumn get peerCallsign => text().named('peer_callsign')();
  IntColumn get lastMessageAt => integer().named('last_message_at')();
  IntColumn get unreadCount =>
      integer().named('unread_count').withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {peerCallsign};
}
