import 'package:drift/drift.dart';

import '../meridian_database.dart';
import '../tables/position_history.dart';
import '../tables/stations.dart';

part 'station_dao.g.dart';

@DriftAccessor(tables: [Stations, PositionHistory])
class StationDao extends DatabaseAccessor<MeridianDatabase>
    with _$StationDaoMixin {
  StationDao(super.db);

  /// Upsert a station by callsign.
  Future<void> upsertStation(StationsCompanion station) =>
      into(stations).insertOnConflictUpdate(station);

  /// Append a position-history entry for an existing station.
  Future<void> appendPositionHistory(PositionHistoryCompanion entry) =>
      into(positionHistory).insert(entry);

  /// Atomic upsert + previous-position append + per-station history cap in
  /// one transaction. Preserves the merge semantics previously implemented
  /// in `StationService._mergeStation`.
  ///
  /// When [previousPosition] is non-null it is appended before the upsert;
  /// when [capHistoryAt] is non-null, any rows older than the most recent
  /// [capHistoryAt] entries for this callsign are deleted in the same
  /// transaction.
  Future<void> upsertWithPositionHistory({
    required StationsCompanion station,
    PositionHistoryCompanion? previousPosition,
    int? capHistoryAt,
  }) {
    return transaction(() async {
      if (previousPosition != null) {
        await into(positionHistory).insert(previousPosition);
      }
      await into(stations).insertOnConflictUpdate(station);
      if (capHistoryAt != null && previousPosition != null) {
        await _capHistoryFor(
          callsign: previousPosition.callsign.value,
          maxEntries: capHistoryAt,
        );
      }
    });
  }

  Future<void> _capHistoryFor({
    required String callsign,
    required int maxEntries,
  }) async {
    await customStatement(
      'DELETE FROM position_history '
      'WHERE callsign = ? '
      'AND id NOT IN ('
      '  SELECT id FROM position_history '
      '  WHERE callsign = ? '
      '  ORDER BY timestamp DESC LIMIT ?'
      ')',
      [callsign, callsign, maxEntries],
    );
  }

  /// Remove a station (and via FK cascade, its position history) by
  /// callsign. Used by Object/Item "killed" packets.
  Future<int> deleteByCallsign(String callsign) =>
      (delete(stations)..where((s) => s.callsign.equals(callsign))).go();

  Stream<List<StationRow>> watchAllStations() => select(stations).watch();

  Stream<StationRow?> watchStation(String callsign) => (select(
    stations,
  )..where((s) => s.callsign.equals(callsign))).watchSingleOrNull();

  /// One-shot read of a single station row (used inside the merge transaction).
  Future<StationRow?> getStation(String callsign) => (select(
    stations,
  )..where((s) => s.callsign.equals(callsign))).getSingleOrNull();

  Future<List<StationRow>> getAllStations() => select(stations).get();

  Future<List<PositionHistoryRow>> getPositionHistory(String callsign) =>
      (select(positionHistory)
            ..where((p) => p.callsign.equals(callsign))
            ..orderBy([(p) => OrderingTerm.asc(p.timestamp)]))
          .get();

  /// All position-history rows across every station, ordered by callsign
  /// then ascending timestamp. Used to rebuild the in-memory cache without
  /// issuing one query per station.
  Future<List<PositionHistoryRow>> getAllPositionHistory() =>
      (select(positionHistory)..orderBy([
            (p) => OrderingTerm.asc(p.callsign),
            (p) => OrderingTerm.asc(p.timestamp),
          ]))
          .get();

  /// Delete stations whose `last_heard` is older than [cutoff].
  /// Position-history rows for those stations are CASCADE-deleted.
  Future<int> pruneOlderThan(DateTime cutoff) {
    final cutoffMs = cutoff.millisecondsSinceEpoch;
    return (delete(
      stations,
    )..where((s) => s.lastHeard.isSmallerThanValue(cutoffMs))).go();
  }

  Future<void> clearAll() async {
    await delete(positionHistory).go();
    await delete(stations).go();
  }
}
