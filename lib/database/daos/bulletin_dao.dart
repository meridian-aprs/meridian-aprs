import 'package:drift/drift.dart';

import '../meridian_database.dart';
import '../tables/bulletins.dart';
import '../tables/outgoing_bulletins.dart';

part 'bulletin_dao.g.dart';

@DriftAccessor(tables: [Bulletins, OutgoingBulletins])
class BulletinDao extends DatabaseAccessor<MeridianDatabase>
    with _$BulletinDaoMixin {
  BulletinDao(super.db);

  // ---------------------------------------------------------------------------
  // Incoming bulletins
  // ---------------------------------------------------------------------------

  /// Upsert keyed by `(source_callsign, addressee)` per ADR-057.
  Future<void> upsertIncoming(BulletinsCompanion bulletin) =>
      into(bulletins).insertOnConflictUpdate(bulletin);

  /// One-shot read of all incoming bulletins, newest `last_heard_at` first.
  Future<List<BulletinRow>> getAllIncoming() {
    return (select(
      bulletins,
    )..orderBy([(b) => OrderingTerm.desc(b.lastHeardAt)])).get();
  }

  Future<int> markIncomingRead(String source, String addressee) {
    return (update(bulletins)..where(
          (b) =>
              b.sourceCallsign.equals(source) & b.addressee.equals(addressee),
        ))
        .write(const BulletinsCompanion(isRead: Value(true)));
  }

  Future<int> deleteIncoming(String source, String addressee) {
    return (delete(bulletins)..where(
          (b) =>
              b.sourceCallsign.equals(source) & b.addressee.equals(addressee),
        ))
        .go();
  }

  /// Delete incoming bulletins whose `last_heard_at` is older than [cutoff].
  Future<int> pruneIncomingOlderThan(DateTime cutoff) {
    final cutoffMs = cutoff.millisecondsSinceEpoch;
    return (delete(
      bulletins,
    )..where((b) => b.lastHeardAt.isSmallerThanValue(cutoffMs))).go();
  }

  // ---------------------------------------------------------------------------
  // Outgoing bulletins
  // ---------------------------------------------------------------------------

  Future<int> insertOutgoing(OutgoingBulletinsCompanion bulletin) =>
      into(outgoingBulletins).insert(bulletin);

  Future<int> updateOutgoingContent({
    required int id,
    String? addressee,
    String? body,
  }) {
    return (update(outgoingBulletins)..where((o) => o.id.equals(id))).write(
      OutgoingBulletinsCompanion(
        addressee: addressee == null ? const Value.absent() : Value(addressee),
        body: body == null ? const Value.absent() : Value(body),
        lastTransmittedAt: const Value(null),
        transmissionCount: const Value(0),
      ),
    );
  }

  Future<int> updateOutgoingSchedule({
    required int id,
    int? intervalSeconds,
    DateTime? expiresAt,
    bool? viaRf,
    bool? viaAprsIs,
  }) {
    return (update(outgoingBulletins)..where((o) => o.id.equals(id))).write(
      OutgoingBulletinsCompanion(
        intervalSeconds: intervalSeconds == null
            ? const Value.absent()
            : Value(intervalSeconds),
        expiresAt: expiresAt == null
            ? const Value.absent()
            : Value(expiresAt.millisecondsSinceEpoch),
        viaRf: viaRf == null ? const Value.absent() : Value(viaRf),
        viaAprsIs: viaAprsIs == null ? const Value.absent() : Value(viaAprsIs),
      ),
    );
  }

  Future<int> recordOutgoingTransmission(int id, DateTime ts) {
    return customUpdate(
      'UPDATE outgoing_bulletins '
      'SET last_transmitted_at = ?, transmission_count = transmission_count + 1 '
      'WHERE id = ?',
      variables: [Variable<int>(ts.millisecondsSinceEpoch), Variable<int>(id)],
      updates: {outgoingBulletins},
    );
  }

  Future<int> setOutgoingEnabled(int id, bool enabled) {
    return (update(outgoingBulletins)..where((o) => o.id.equals(id))).write(
      OutgoingBulletinsCompanion(enabled: Value(enabled)),
    );
  }

  Future<int> deleteOutgoing(int id) =>
      (delete(outgoingBulletins)..where((o) => o.id.equals(id))).go();

  /// One-shot read of all outgoing bulletins, oldest first. Used by `load()`
  /// on the main isolate and by the background isolate's bulletin timer.
  Future<List<OutgoingBulletinRow>> getAllOutgoing() {
    return (select(
      outgoingBulletins,
    )..orderBy([(o) => OrderingTerm.asc(o.createdAt)])).get();
  }
}
