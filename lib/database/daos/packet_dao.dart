import 'package:drift/drift.dart';

import '../meridian_database.dart';
import '../tables/packets.dart';

part 'packet_dao.g.dart';

@DriftAccessor(tables: [Packets])
class PacketDao extends DatabaseAccessor<MeridianDatabase>
    with _$PacketDaoMixin {
  PacketDao(super.db);

  Future<int> insertPacket(PacketsCompanion packet) =>
      into(packets).insert(packet);

  /// Stream of the most-recent packets, newest first. Default limit matches
  /// the in-memory rolling buffer cap previously used by `StationService`.
  Stream<List<PacketRow>> watchRecent({int limit = 5000}) {
    return (select(packets)
          ..orderBy([(p) => OrderingTerm.desc(p.receivedAt)])
          ..limit(limit))
        .watch();
  }

  Future<int> pruneOlderThan(DateTime cutoff) {
    final cutoffMs = cutoff.millisecondsSinceEpoch;
    return (delete(
      packets,
    )..where((p) => p.receivedAt.isSmallerThanValue(cutoffMs))).go();
  }

  Future<void> clearAll() => delete(packets).go();
}
