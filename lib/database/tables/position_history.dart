import 'package:drift/drift.dart';

import 'stations.dart';

@DataClassName('PositionHistoryRow')
class PositionHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get callsign =>
      text().references(Stations, #callsign, onDelete: KeyAction.cascade)();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  IntColumn get timestamp => integer()();
}
