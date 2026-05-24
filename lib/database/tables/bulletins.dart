import 'package:drift/drift.dart';

import '../../models/bulletin.dart';
import '../converters/bulletin_transports_converter.dart';

/// Incoming bulletins. Unique on `(source_callsign, addressee)` per ADR-057 —
/// retransmissions update the row rather than appending.
@DataClassName('BulletinRow')
class Bulletins extends Table {
  TextColumn get sourceCallsign => text().named('source_callsign')();
  TextColumn get addressee => text()();
  TextColumn get body => text()();
  IntColumn get firstHeardAt => integer().named('first_heard_at')();
  IntColumn get lastHeardAt => integer().named('last_heard_at')();
  IntColumn get heardCount =>
      integer().named('heard_count').withDefault(const Constant(1))();
  TextColumn get category =>
      text().map(const EnumNameConverter(BulletinCategory.values))();
  TextColumn get lineNumber => text().named('line_number')();
  TextColumn get groupName => text().named('group_name').nullable()();
  TextColumn get transports => text()
      .map(const BulletinTransportsConverter())
      .withDefault(const Constant(''))();
  RealColumn get receivedLat => real().named('received_lat').nullable()();
  RealColumn get receivedLon => real().named('received_lon').nullable()();
  BoolColumn get isRead =>
      boolean().named('is_read').withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {sourceCallsign, addressee};
}
