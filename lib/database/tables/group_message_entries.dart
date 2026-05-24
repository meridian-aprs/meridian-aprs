import 'package:drift/drift.dart';

/// Group-channel messages keyed by group name. Group subscriptions
/// themselves remain in SharedPreferences (see ADR-062).
@DataClassName('GroupMessageEntryRow')
class GroupMessageEntries extends Table {
  TextColumn get id => text()();
  TextColumn get groupName => text().named('group_name')();
  TextColumn get fromCallsign => text().named('from_callsign')();
  TextColumn get body => text()();
  IntColumn get timestamp => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
