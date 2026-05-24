// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'station_dao.dart';

// ignore_for_file: type=lint
mixin _$StationDaoMixin on DatabaseAccessor<MeridianDatabase> {
  $StationsTable get stations => attachedDatabase.stations;
  $PositionHistoryTable get positionHistory => attachedDatabase.positionHistory;
  StationDaoManager get managers => StationDaoManager(this);
}

class StationDaoManager {
  final _$StationDaoMixin _db;
  StationDaoManager(this._db);
  $$StationsTableTableManager get stations =>
      $$StationsTableTableManager(_db.attachedDatabase, _db.stations);
  $$PositionHistoryTableTableManager get positionHistory =>
      $$PositionHistoryTableTableManager(
        _db.attachedDatabase,
        _db.positionHistory,
      );
}
