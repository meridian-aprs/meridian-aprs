/// Receive-side bulletin store + outgoing-bulletin registry (ADR-062).
///
/// Ingests classified bulletin packets from [MessageService] and upserts them
/// into a `(sourceCallsign, addressee)`-keyed store. Retransmissions update
/// the existing row: body replaces (marking unread if changed), `lastHeardAt`
/// bumps, `heardCount` increments, `transports` union-merges.
///
/// Persistence (ADR-062):
///   - **Incoming** bulletins are an in-memory working set written through to
///     drift (`bulletins` table, keyed by source|addressee). The model's `id`
///     is a session-scoped navigation handle assigned in memory — it is NOT
///     persisted (the table is keyed by source+addressee). The background
///     isolate never ingests incoming bulletins, so no watch is needed here.
///   - **Outgoing** bulletins use the drift autoincrement `id`. The in-memory
///     `_outgoing` cache is updated by main-isolate write-through and re-read
///     fresh from the shared DB by [refreshOutgoing] (called at the start of
///     every [BulletinScheduler] tick). Because the background isolate writes
///     transmission updates to the *same* `meridian.db`, the next main-isolate
///     tick observes them without the operator triggering anything — this is
///     the ADR-057/061 fix. The mechanism is polled (bounded by the 30 s tick),
///     not a drift `watch()`: a continuous watch raced with write-through
///     (a lagging emission carrying a pre-mutation snapshot could revert the
///     cache), so it was deliberately dropped.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/packet/aprs_packet.dart';
import '../core/util/clock.dart';
import '../database/daos/bulletin_dao.dart';
import '../database/meridian_database.dart'
    show
        BulletinRow,
        BulletinsCompanion,
        OutgoingBulletinRow,
        OutgoingBulletinsCompanion;
import '../models/bulletin.dart';
import '../models/outgoing_bulletin.dart';
import 'bulletin_subscription_service.dart';

/// Outcome of [BulletinService.ingest], exposed for test assertions.
enum BulletinIngestOutcome {
  /// New row inserted.
  inserted,

  /// Existing row updated in place (retransmission).
  updated,

  /// Dropped before upsert — named group not subscribed, or other future
  /// scope filter.
  dropped,
}

class BulletinService extends ChangeNotifier {
  BulletinService({
    required BulletinSubscriptionService subscriptions,
    required BulletinDao bulletinDao,
    SharedPreferences? prefs,
    Clock clock = DateTime.now,
  }) : _subscriptions = subscriptions,
       _bulletinDao = bulletinDao,
       _prefsOverride = prefs,
       _clock = clock;

  final BulletinSubscriptionService _subscriptions;
  final BulletinDao _bulletinDao;
  final SharedPreferences? _prefsOverride;
  final Clock _clock;

  // Settings keys (stay in SharedPreferences — structured data is in drift).
  static const _keyShowBulletins = 'bulletins_show';
  static const _keyRadiusKm = 'bulletins_radius_km';
  static const _keyRetentionHours = 'bulletins_retention_hours';

  /// Allowed TX-interval options (seconds). `0` = one-shot.
  static const List<int> intervalOptionsSeconds = [
    0,
    300,
    600,
    900,
    1800,
    3600,
  ];

  /// Allowed expiry options (hours since creation).
  static const List<int> expiryOptionsHours = [2, 6, 12, 24, 48];

  /// Allowed radius options (km). `0` = "Map area only"; `-1` = "Global".
  static const List<int> radiusOptionsKm = [0, 100, 500, 1000, -1];

  /// Allowed retention options (hours). Default 48h (APRSIS32 convention).
  static const List<int> retentionOptionsHours = [24, 48, 72];

  // Incoming bulletins keyed by "SOURCE|ADDRESSEE". In-memory working set,
  // written through to drift. `id` assigned in-memory (session-scoped).
  final Map<String, Bulletin> _bulletins = {};
  int _nextId = 1;

  // Outgoing bulletins by drift id. Updated by main-isolate write-through and
  // by [refreshOutgoing] (fresh DB read each scheduler tick).
  final Map<int, OutgoingBulletin> _outgoing = {};

  bool _showBulletins = true;
  int _radiusKm = 500;
  int _retentionHours = 48;

  double? _operatorLat;
  double? _operatorLon;

  /// Update the operator's position used for distance filtering. Pass
  /// `(null, null)` to clear.
  void setOperatorLocation({double? lat, double? lon}) {
    if (_operatorLat == lat && _operatorLon == lon) return;
    _operatorLat = lat;
    _operatorLon = lon;
  }

  bool get showBulletins => _showBulletins;
  int get radiusKm => _radiusKm;
  int get retentionHours => _retentionHours;

  /// All stored bulletins, newest `lastHeardAt` first.
  List<Bulletin> get bulletins {
    final list = _bulletins.values.toList()
      ..sort((a, b) => b.lastHeardAt.compareTo(a.lastHeardAt));
    return list;
  }

  int get unreadCount => _bulletins.values.where((b) => !b.isRead).length;

  /// All outgoing bulletins in insertion order (oldest first).
  List<OutgoingBulletin> get outgoingBulletins {
    final list = _outgoing.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return List.unmodifiable(list);
  }

  OutgoingBulletin? outgoingById(int id) => _outgoing[id];

  Future<void> load() async {
    final prefs = await _prefs();
    _showBulletins = prefs.getBool(_keyShowBulletins) ?? true;
    _radiusKm = prefs.getInt(_keyRadiusKm) ?? 500;
    _retentionHours = prefs.getInt(_keyRetentionHours) ?? 48;

    // Incoming — assign session-scoped ids as we hydrate.
    _bulletins.clear();
    _nextId = 1;
    for (final row in await _bulletinDao.getAllIncoming()) {
      final b = _rowToBulletin(row, _nextId++);
      _bulletins[_key(b.sourceCallsign, b.addressee)] = b;
    }

    // Outgoing — explicit read (don't depend on the watch's first emission).
    _outgoing.clear();
    for (final row in await _bulletinDao.getAllOutgoing()) {
      _outgoing[row.id] = _rowToOutgoing(row);
    }

    notifyListeners();
  }

  /// Ingest a classified bulletin. Returns the outcome so callers/tests can
  /// distinguish first-receipt from retransmission.
  BulletinIngestOutcome ingest({
    required BulletinAddresseeInfo info,
    required String sourceCallsign,
    required String body,
    required PacketSource transport,
    required DateTime receivedAt,
    double? receivedLat,
    double? receivedLon,
  }) {
    // Named-group subscription filter.
    if (info.category == BulletinCategory.groupNamed) {
      final group = info.groupName;
      if (group == null ||
          group.isEmpty ||
          !_subscriptions.subscribedGroupNames.contains(group)) {
        return BulletinIngestOutcome.dropped;
      }
    }

    // Client-side distance filter for general APRS-IS bulletins (ADR-058).
    if (info.category == BulletinCategory.general &&
        transport == PacketSource.aprsIs &&
        _radiusKm > 0 &&
        _operatorLat != null &&
        _operatorLon != null &&
        receivedLat != null &&
        receivedLon != null) {
      final km = _haversineKm(
        _operatorLat!,
        _operatorLon!,
        receivedLat,
        receivedLon,
      );
      if (km > _radiusKm) return BulletinIngestOutcome.dropped;
    }

    final source = sourceCallsign.trim().toUpperCase();
    final key = _key(source, info.addressee);
    final existing = _bulletins[key];
    final BulletinIngestOutcome outcome;
    final Bulletin stored;

    if (existing == null) {
      stored = Bulletin(
        id: _nextId++,
        sourceCallsign: source,
        addressee: info.addressee,
        category: info.category,
        lineNumber: info.lineNumber,
        groupName: info.groupName,
        body: body,
        firstHeardAt: receivedAt,
        lastHeardAt: receivedAt,
        heardCount: 1,
        transports: {transport.asBulletinTransport},
        receivedLat: receivedLat,
        receivedLon: receivedLon,
        isRead: false,
      );
      outcome = BulletinIngestOutcome.inserted;
    } else {
      final bodyChanged = existing.body != body;
      final mergedTransports = {
        ...existing.transports,
        transport.asBulletinTransport,
      };
      stored = existing.copyWith(
        body: bodyChanged ? body : existing.body,
        lastHeardAt: receivedAt,
        heardCount: existing.heardCount + 1,
        transports: mergedTransports,
        isRead: bodyChanged ? false : existing.isRead,
      );
      outcome = BulletinIngestOutcome.updated;
    }

    _bulletins[key] = stored;
    _bulletinDao.upsertIncoming(
      _bulletinToCompanion(stored),
    ); // ignore: unawaited_futures
    notifyListeners();
    return outcome;
  }

  /// Mark a bulletin as read.
  Future<void> markRead(int id) async {
    String? matchKey;
    for (final e in _bulletins.entries) {
      if (e.value.id == id) {
        matchKey = e.key;
        break;
      }
    }
    if (matchKey == null) return;
    final current = _bulletins[matchKey]!;
    if (current.isRead) return;
    _bulletins[matchKey] = current.copyWith(isRead: true);
    await _bulletinDao.markIncomingRead(
      current.sourceCallsign,
      current.addressee,
    );
    notifyListeners();
  }

  Future<void> setShowBulletins(bool v) async {
    if (_showBulletins == v) return;
    _showBulletins = v;
    final prefs = await _prefs();
    await prefs.setBool(_keyShowBulletins, v);
    notifyListeners();
  }

  Future<void> setRadiusKm(int v) async {
    if (_radiusKm == v) return;
    if (!radiusOptionsKm.contains(v)) {
      throw ArgumentError.value(v, 'radiusKm', 'not a supported radius');
    }
    _radiusKm = v;
    final prefs = await _prefs();
    await prefs.setInt(_keyRadiusKm, v);
    notifyListeners();
  }

  Future<void> setRetentionHours(int v) async {
    if (_retentionHours == v) return;
    if (!retentionOptionsHours.contains(v)) {
      throw ArgumentError.value(
        v,
        'retentionHours',
        'not a supported retention',
      );
    }
    _retentionHours = v;
    final prefs = await _prefs();
    await prefs.setInt(_keyRetentionHours, v);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // OutgoingBulletin CRUD (ADR-057)
  // ---------------------------------------------------------------------------

  /// Create a new outgoing bulletin. Starts enabled with `lastTransmittedAt`
  /// null, so the scheduler fires an initial pulse on its next tick. The id is
  /// assigned by drift (autoincrement).
  Future<OutgoingBulletin> createOutgoing({
    required String addressee,
    required String body,
    int intervalSeconds = 1800,
    DateTime? expiresAt,
    bool viaRf = true,
    bool viaAprsIs = true,
  }) async {
    if (!intervalOptionsSeconds.contains(intervalSeconds)) {
      throw ArgumentError.value(
        intervalSeconds,
        'intervalSeconds',
        'not a supported interval',
      );
    }
    final normalized = addressee.trim().toUpperCase();
    if (!_bulletinAddresseePattern.hasMatch(normalized)) {
      throw ArgumentError.value(
        addressee,
        'addressee',
        'invalid bulletin addressee — must be BLN[0-9A-Z][NAME]',
      );
    }
    final now = _clock();
    final resolvedExpiry = expiresAt ?? now.add(const Duration(hours: 24));
    final id = await _bulletinDao.insertOutgoing(
      OutgoingBulletinsCompanion.insert(
        addressee: normalized,
        body: body,
        intervalSeconds: intervalSeconds,
        createdAt: now.millisecondsSinceEpoch,
        expiresAt: Value(resolvedExpiry.millisecondsSinceEpoch),
        viaRf: Value(viaRf),
        viaAprsIs: Value(viaAprsIs),
      ),
    );
    final ob = OutgoingBulletin(
      id: id,
      addressee: normalized,
      body: body,
      intervalSeconds: intervalSeconds,
      expiresAt: resolvedExpiry,
      createdAt: now,
      viaRf: viaRf,
      viaAprsIs: viaAprsIs,
      enabled: true,
    );
    _outgoing[id] = ob;
    notifyListeners();
    return ob;
  }

  /// Update body/addressee. Resets `lastTransmittedAt` and `transmissionCount`
  /// so the scheduler fires a fresh initial pulse (ADR-057).
  Future<void> updateOutgoingContent(
    int id, {
    String? addressee,
    String? body,
  }) async {
    final current = _outgoing[id];
    if (current == null) return;
    String? nextAddressee;
    if (addressee != null) {
      final normalized = addressee.trim().toUpperCase();
      if (!_bulletinAddresseePattern.hasMatch(normalized)) {
        throw ArgumentError.value(addressee, 'addressee', 'invalid');
      }
      nextAddressee = normalized;
    }
    await _bulletinDao.updateOutgoingContent(
      id: id,
      addressee: nextAddressee,
      body: body,
    );
    _outgoing[id] = current.copyWith(
      addressee: nextAddressee,
      body: body,
      clearLastTransmittedAt: true,
      transmissionCount: 0,
    );
    notifyListeners();
  }

  /// Update the schedule (interval, expiry, transport flags). Does NOT reset
  /// `lastTransmittedAt`/`transmissionCount` (ADR-057).
  Future<void> updateOutgoingSchedule(
    int id, {
    int? intervalSeconds,
    DateTime? expiresAt,
    bool? viaRf,
    bool? viaAprsIs,
  }) async {
    final current = _outgoing[id];
    if (current == null) return;
    if (intervalSeconds != null &&
        !intervalOptionsSeconds.contains(intervalSeconds)) {
      throw ArgumentError.value(
        intervalSeconds,
        'intervalSeconds',
        'not a supported interval',
      );
    }
    await _bulletinDao.updateOutgoingSchedule(
      id: id,
      intervalSeconds: intervalSeconds,
      expiresAt: expiresAt,
      viaRf: viaRf,
      viaAprsIs: viaAprsIs,
    );
    _outgoing[id] = current.copyWith(
      intervalSeconds: intervalSeconds,
      expiresAt: expiresAt,
      viaRf: viaRf,
      viaAprsIs: viaAprsIs,
    );
    notifyListeners();
  }

  /// Enable or disable an outgoing bulletin without editing content/schedule.
  Future<void> setOutgoingEnabled(int id, bool enabled) async {
    final current = _outgoing[id];
    if (current == null) return;
    if (current.enabled == enabled) return;
    await _bulletinDao.setOutgoingEnabled(id, enabled);
    _outgoing[id] = current.copyWith(enabled: enabled);
    notifyListeners();
  }

  /// Delete an outgoing bulletin permanently.
  Future<void> deleteOutgoing(int id) async {
    if (!_outgoing.containsKey(id)) return;
    await _bulletinDao.deleteOutgoing(id);
    _outgoing.remove(id);
    notifyListeners();
  }

  /// Called by [BulletinScheduler] after a successful transmission. Bumps the
  /// counter and stamps `lastTransmittedAt`.
  Future<void> recordOutgoingTransmission(int id, DateTime timestamp) async {
    final current = _outgoing[id];
    if (current == null) return;
    await _bulletinDao.recordOutgoingTransmission(id, timestamp);
    _outgoing[id] = current.copyWith(
      lastTransmittedAt: timestamp,
      transmissionCount: current.transmissionCount + 1,
    );
    notifyListeners();
  }

  /// Matches bulletin addressees per APRS spec §3.2.16.
  static final RegExp _bulletinAddresseePattern = RegExp(
    r'^BLN[0-9A-Z][A-Z0-9]{0,5}$',
  );

  // ---------------------------------------------------------------------------
  // Retention sweeper
  // ---------------------------------------------------------------------------

  /// Drop all incoming bulletins whose `lastHeardAt` is older than [retention].
  Future<void> pruneOlderThan(Duration retention) async {
    final cutoff = _clock().subtract(retention);
    final before = _bulletins.length;
    _bulletins.removeWhere((_, b) => b.lastHeardAt.isBefore(cutoff));
    await _bulletinDao.pruneIncomingOlderThan(cutoff);
    if (_bulletins.length == before) return;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Fresh re-read (absorbs background-isolate outgoing writes via shared DB)
  // ---------------------------------------------------------------------------

  /// Rebuild the outgoing cache from the shared database. Called at the start
  /// of every [BulletinScheduler] tick so background-isolate transmission
  /// updates surface in the main isolate without the operator triggering
  /// anything (ADR-057/061). Also safe to call from a resume handler.
  Future<void> refreshOutgoing() async {
    final rows = await _bulletinDao.getAllOutgoing();
    _outgoing
      ..clear()
      ..addEntries(rows.map((r) => MapEntry(r.id, _rowToOutgoing(r))));
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Row <-> model conversion
  // ---------------------------------------------------------------------------

  Bulletin _rowToBulletin(BulletinRow row, int id) => Bulletin(
    id: id,
    sourceCallsign: row.sourceCallsign,
    addressee: row.addressee,
    category: row.category,
    lineNumber: row.lineNumber,
    groupName: row.groupName,
    body: row.body,
    firstHeardAt: DateTime.fromMillisecondsSinceEpoch(row.firstHeardAt),
    lastHeardAt: DateTime.fromMillisecondsSinceEpoch(row.lastHeardAt),
    heardCount: row.heardCount,
    transports: row.transports,
    receivedLat: row.receivedLat,
    receivedLon: row.receivedLon,
    isRead: row.isRead,
  );

  BulletinsCompanion _bulletinToCompanion(Bulletin b) =>
      BulletinsCompanion.insert(
        sourceCallsign: b.sourceCallsign,
        addressee: b.addressee,
        body: b.body,
        firstHeardAt: b.firstHeardAt.millisecondsSinceEpoch,
        lastHeardAt: b.lastHeardAt.millisecondsSinceEpoch,
        category: b.category,
        lineNumber: b.lineNumber,
        groupName: Value(b.groupName),
        heardCount: Value(b.heardCount),
        transports: Value(b.transports),
        receivedLat: Value(b.receivedLat),
        receivedLon: Value(b.receivedLon),
        isRead: Value(b.isRead),
      );

  OutgoingBulletin _rowToOutgoing(OutgoingBulletinRow row) => OutgoingBulletin(
    id: row.id,
    addressee: row.addressee,
    body: row.body,
    intervalSeconds: row.intervalSeconds,
    expiresAt: row.expiresAt != null
        ? DateTime.fromMillisecondsSinceEpoch(row.expiresAt!)
        : DateTime.fromMillisecondsSinceEpoch(
            row.createdAt,
          ).add(const Duration(hours: 24)),
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
    lastTransmittedAt: row.lastTransmittedAt != null
        ? DateTime.fromMillisecondsSinceEpoch(row.lastTransmittedAt!)
        : null,
    transmissionCount: row.transmissionCount,
    viaRf: row.viaRf,
    viaAprsIs: row.viaAprsIs,
    enabled: row.enabled,
  );

  String _key(String source, String addressee) =>
      '${source.toUpperCase()}|${addressee.toUpperCase()}';

  static double _haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _deg2rad(double d) => d * math.pi / 180.0;

  Future<SharedPreferences> _prefs() async =>
      _prefsOverride ?? await SharedPreferences.getInstance();
}
