// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'packet_dao.dart';

// ignore_for_file: type=lint
mixin _$PacketDaoMixin on DatabaseAccessor<MeridianDatabase> {
  $PacketsTable get packets => attachedDatabase.packets;
  PacketDaoManager get managers => PacketDaoManager(this);
}

class PacketDaoManager {
  final _$PacketDaoMixin _db;
  PacketDaoManager(this._db);
  $$PacketsTableTableManager get packets =>
      $$PacketsTableTableManager(_db.attachedDatabase, _db.packets);
}
