import 'package:drift/drift.dart';

import '../../models/bulletin.dart';

/// Stores `Set<BulletinTransport>` as a comma-joined `text` column.
/// Unknown tokens are silently dropped (forward-compat with future
/// transports), preserving the canonical small set.
class BulletinTransportsConverter
    extends TypeConverter<Set<BulletinTransport>, String> {
  const BulletinTransportsConverter();

  @override
  Set<BulletinTransport> fromSql(String fromDb) {
    if (fromDb.isEmpty) return <BulletinTransport>{};
    return fromDb
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map(
          (name) =>
              BulletinTransport.values.where((t) => t.name == name).firstOrNull,
        )
        .whereType<BulletinTransport>()
        .toSet();
  }

  @override
  String toSql(Set<BulletinTransport> value) =>
      value.map((t) => t.name).join(',');
}
