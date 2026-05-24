// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message_dao.dart';

// ignore_for_file: type=lint
mixin _$MessageDaoMixin on DatabaseAccessor<MeridianDatabase> {
  $ConversationsTable get conversations => attachedDatabase.conversations;
  $MessageEntriesTable get messageEntries => attachedDatabase.messageEntries;
  $GroupMessageEntriesTable get groupMessageEntries =>
      attachedDatabase.groupMessageEntries;
  MessageDaoManager get managers => MessageDaoManager(this);
}

class MessageDaoManager {
  final _$MessageDaoMixin _db;
  MessageDaoManager(this._db);
  $$ConversationsTableTableManager get conversations =>
      $$ConversationsTableTableManager(_db.attachedDatabase, _db.conversations);
  $$MessageEntriesTableTableManager get messageEntries =>
      $$MessageEntriesTableTableManager(
        _db.attachedDatabase,
        _db.messageEntries,
      );
  $$GroupMessageEntriesTableTableManager get groupMessageEntries =>
      $$GroupMessageEntriesTableTableManager(
        _db.attachedDatabase,
        _db.groupMessageEntries,
      );
}
