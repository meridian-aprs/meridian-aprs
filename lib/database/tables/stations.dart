import 'package:drift/drift.dart';

import '../../core/packet/station.dart';

@DataClassName('StationRow')
class Stations extends Table {
  TextColumn get callsign => text()();
  TextColumn get symbolTable => text().named('symbol_table')();
  TextColumn get symbolCode => text().named('symbol_code')();
  TextColumn get comment => text()();
  TextColumn get rawPacket => text().named('raw_packet')();
  TextColumn get device => text().nullable()();
  IntColumn get lastHeard => integer().named('last_heard')();
  TextColumn get stationType => text()
      .named('station_type')
      .map(const EnumNameConverter(StationType.values))();
  TextColumn get messageCapability => text()
      .named('message_capability')
      .map(const EnumNameConverter(MessageCapability.values))();
  TextColumn get capabilities => text().nullable()();
  RealColumn get lat => real()();
  RealColumn get lon => real()();

  @override
  Set<Column> get primaryKey => {callsign};
}
