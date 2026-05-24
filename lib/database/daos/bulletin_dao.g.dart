// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bulletin_dao.dart';

// ignore_for_file: type=lint
mixin _$BulletinDaoMixin on DatabaseAccessor<MeridianDatabase> {
  $BulletinsTable get bulletins => attachedDatabase.bulletins;
  $OutgoingBulletinsTable get outgoingBulletins =>
      attachedDatabase.outgoingBulletins;
  BulletinDaoManager get managers => BulletinDaoManager(this);
}

class BulletinDaoManager {
  final _$BulletinDaoMixin _db;
  BulletinDaoManager(this._db);
  $$BulletinsTableTableManager get bulletins =>
      $$BulletinsTableTableManager(_db.attachedDatabase, _db.bulletins);
  $$OutgoingBulletinsTableTableManager get outgoingBulletins =>
      $$OutgoingBulletinsTableTableManager(
        _db.attachedDatabase,
        _db.outgoingBulletins,
      );
}
