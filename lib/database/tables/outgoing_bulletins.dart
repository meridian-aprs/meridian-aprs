import 'package:drift/drift.dart';

/// Operator-scheduled outgoing bulletins. `id` is an auto-incremented integer
/// to preserve the existing int-id contract (see ADR-062 plan deviation
/// note).
@DataClassName('OutgoingBulletinRow')
class OutgoingBulletins extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get addressee => text()();
  TextColumn get body => text()();
  IntColumn get intervalSeconds => integer().named('interval_seconds')();
  IntColumn get transmissionCount =>
      integer().named('transmission_count').withDefault(const Constant(0))();
  IntColumn get expiresAt => integer().named('expires_at').nullable()();
  IntColumn get createdAt => integer().named('created_at')();
  IntColumn get lastTransmittedAt =>
      integer().named('last_transmitted_at').nullable()();
  BoolColumn get viaRf =>
      boolean().named('via_rf').withDefault(const Constant(true))();
  BoolColumn get viaAprsIs =>
      boolean().named('via_aprs_is').withDefault(const Constant(true))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
}
