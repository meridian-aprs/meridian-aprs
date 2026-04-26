/// Receive-side bulletin store.
///
/// Ingests classified bulletin packets from [MessageService] and upserts
/// them into a `(sourceCallsign, addressee)`-keyed store. Retransmissions
/// update the existing row: body replaces (marking unread if changed),
/// `lastHeardAt` bumps, `heardCount` increments, `transports` union-merges.
///
/// For v0.17 PR 1 this service only applies the named-group subscription
/// filter (unsubscribed `BLNxNAME` dropped). General `BLN0`–`BLN9` scope
/// filtering (distance, station-location-null banner) lands in PR 5 along
/// with the APRS-IS filter extension. See ADR-057, ADR-058.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/packet/aprs_packet.dart';
import '../core/util/clock.dart';
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
  /// scope filter (PR 5).
  dropped,
}

class BulletinService extends ChangeNotifier {
  BulletinService({
    required BulletinSubscriptionService subscriptions,
    SharedPreferences? prefs,
    Clock clock = DateTime.now,
  }) : _subscriptions = subscriptions,
       _prefsOverride = prefs,
       _clock = clock;

  final BulletinSubscriptionService _subscriptions;
  final SharedPreferences? _prefsOverride;
  final Clock _clock;

  static const _keyBulletins = 'bulletins_v1';
  static const _keyNextId = 'bulletins_next_id_v1';
  static const _keyShowBulletins = 'bulletins_show';
  static const _keyRadiusKm = 'bulletins_radius_km';
  static const _keyRetentionHours = 'bulletins_retention_hours';

  /// SharedPreferences key holding the JSON-encoded list of
  /// [OutgoingBulletin]s. Read directly by the background isolate's bulletin
  /// timer (same pattern as beacon settings), so the key name is public.
  static const keyOutgoingBulletins = 'outgoing_bulletins_v1';
  static const _keyOutgoingNextId = 'outgoing_bulletins_next_id_v1';

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

  /// Allowed radius options (km). `0` is a sentinel for "Map area only" (no
  /// client-side distance filter — the APRS-IS area filter handles it).
  /// The `-1` sentinel means "Global" (no distance filter at all).
  static const List<int> radiusOptionsKm = [0, 100, 500, 1000, -1];

  /// Allowed retention options (hours). Default is 48h (APRSIS32 convention).
  static const List<int> retentionOptionsHours = [24, 48, 72];

  // Keyed by "SOURCE|ADDRESSEE" for stable lookup.
  final Map<String, Bulletin> _bulletins = {};
  int _nextId = 1;

  // Outgoing bulletins by id. Scheduler iterates this in-order per tick.
  final Map<int, OutgoingBulletin> _outgoing = {};
  int _outgoingNextId = 1;

  bool _showBulletins = true;
  int _radiusKm = 500;
  int _retentionHours = 48;

  /// Operator's current position (optional). Pushed in by the owning app
  /// layer when station settings or beacon location change. Used as the
  /// origin for client-side distance filtering of general APRS-IS bulletins
  /// (ADR-058).
  double? _operatorLat;
  double? _operatorLon;

  /// Update the operator's position used for distance filtering. Pass
  /// `(null, null)` to clear.
  void setOperatorLocation({double? lat, double? lon}) {
    if (_operatorLat == lat && _operatorLon == lon) return;
    _operatorLat = lat;
    _operatorLon = lon;
    // No notifyListeners — position does not affect rendered state, only
    // future ingest decisions.
  }

  /// Master toggle for bulletin display. When false, the Bulletins tab hides
  /// all received rows (ingest keeps storing — ADR-054 capture-always parity).
  bool get showBulletins => _showBulletins;

  /// Distance-filter radius in km for APRS-IS-received general bulletins.
  /// `0` = "map area only" (area filter alone); `-1` = "global" (no filter).
  /// Actual distance-filtering logic lands in PR 5 along with the filter
  /// builder; this getter only stores the user preference for now.
  int get radiusKm => _radiusKm;

  int get retentionHours => _retentionHours;

  /// All stored bulletins, newest `lastHeardAt` first.
  List<Bulletin> get bulletins {
    final list = _bulletins.values.toList()
      ..sort((a, b) => b.lastHeardAt.compareTo(a.lastHeardAt));
    return list;
  }

  int get unreadCount => _bulletins.values.where((b) => !b.isRead).length;

  /// All outgoing bulletins in insertion order (oldest first). The scheduler
  /// iterates this list on each tick; the "My bulletins" UI renders it.
  List<OutgoingBulletin> get outgoingBulletins =>
      List.unmodifiable(_outgoing.values);

  OutgoingBulletin? outgoingById(int id) => _outgoing[id];

  Future<void> load() async {
    final prefs = await _prefs();
    _nextId = prefs.getInt(_keyNextId) ?? 1;
    _outgoingNextId = prefs.getInt(_keyOutgoingNextId) ?? 1;
    _showBulletins = prefs.getBool(_keyShowBulletins) ?? true;
    _radiusKm = prefs.getInt(_keyRadiusKm) ?? 500;
    _retentionHours = prefs.getInt(_keyRetentionHours) ?? 48;
    final raw = prefs.getString(_keyBulletins);
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(Bulletin.fromJson);
        _bulletins.clear();
        for (final b in list) {
          _bulletins[_key(b.sourceCallsign, b.addressee)] = b;
        }
      } catch (e) {
        debugPrint('BulletinService: failed to decode bulletins: $e');
      }
    }
    final outgoingRaw = prefs.getString(keyOutgoingBulletins);
    if (outgoingRaw != null) {
      try {
        final list = (jsonDecode(outgoingRaw) as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(OutgoingBulletin.fromJson);
        _outgoing.clear();
        for (final ob in list) {
          _outgoing[ob.id] = ob;
        }
      } catch (e) {
        debugPrint('BulletinService: failed to decode outgoing: $e');
      }
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
    // Only applies when: category is general, transport is APRS-IS, the user
    // has a non-sentinel radius configured, and both endpoints have known
    // positions. If either position is unknown the bulletin is kept — the
    // operator sees it and a banner (UI-only) prompts them to set their
    // location. RF bulletins are never distance-filtered (short-range
    // already). Named groups are never distance-filtered (explicit subscribe).
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

    if (existing == null) {
      _bulletins[key] = Bulletin(
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
      _bulletins[key] = existing.copyWith(
        body: bodyChanged ? body : existing.body,
        lastHeardAt: receivedAt,
        heardCount: existing.heardCount + 1,
        transports: mergedTransports,
        // If the body has changed, re-mark as unread (new information).
        isRead: bodyChanged ? false : existing.isRead,
      );
      outcome = BulletinIngestOutcome.updated;
    }

    _persist(); // ignore: unawaited_futures
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
    await _persist();
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
  // OutgoingBulletin CRUD (v0.17, ADR-057)
  // ---------------------------------------------------------------------------

  /// Create a new outgoing bulletin. Starts enabled with `lastTransmittedAt`
  /// null, so the scheduler fires an initial pulse on its next tick.
  ///
  /// [intervalSeconds] must be one of [intervalOptionsSeconds] (0 = one-shot).
  /// [expiresAt] defaults to `createdAt + 24h` when not supplied.
  /// Throws [ArgumentError] on invalid addressee or interval.
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
    final ob = OutgoingBulletin(
      id: _outgoingNextId++,
      addressee: normalized,
      body: body,
      intervalSeconds: intervalSeconds,
      expiresAt: expiresAt ?? now.add(const Duration(hours: 24)),
      createdAt: now,
      viaRf: viaRf,
      viaAprsIs: viaAprsIs,
      enabled: true,
    );
    _outgoing[ob.id] = ob;
    await _persist();
    notifyListeners();
    return ob;
  }

  /// Update the body and/or addressee of an outgoing bulletin. Per ADR-057
  /// this resets `lastTransmittedAt` and `transmissionCount` so the scheduler
  /// fires a fresh initial pulse on its next tick.
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
    _outgoing[id] = current.copyWith(
      addressee: nextAddressee,
      body: body,
      clearLastTransmittedAt: true,
      transmissionCount: 0,
    );
    await _persist();
    notifyListeners();
  }

  /// Update the schedule (interval, expiry, transport flags). Does NOT reset
  /// `lastTransmittedAt` or `transmissionCount` — this is the explicit contract
  /// per ADR-057 (changing when/where to retransmit ≠ re-sending the body).
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
    _outgoing[id] = current.copyWith(
      intervalSeconds: intervalSeconds,
      expiresAt: expiresAt,
      viaRf: viaRf,
      viaAprsIs: viaAprsIs,
    );
    await _persist();
    notifyListeners();
  }

  /// Enable or disable an outgoing bulletin without editing content/schedule.
  Future<void> setOutgoingEnabled(int id, bool enabled) async {
    final current = _outgoing[id];
    if (current == null) return;
    if (current.enabled == enabled) return;
    _outgoing[id] = current.copyWith(enabled: enabled);
    await _persist();
    notifyListeners();
  }

  /// Delete an outgoing bulletin permanently.
  Future<void> deleteOutgoing(int id) async {
    if (_outgoing.remove(id) == null) return;
    await _persist();
    notifyListeners();
  }

  /// Called by [BulletinScheduler] after a successful transmission. Bumps the
  /// counter and stamps `lastTransmittedAt`.
  Future<void> recordOutgoingTransmission(int id, DateTime timestamp) async {
    final current = _outgoing[id];
    if (current == null) return;
    _outgoing[id] = current.copyWith(
      lastTransmittedAt: timestamp,
      transmissionCount: current.transmissionCount + 1,
    );
    await _persist();
    notifyListeners();
  }

  /// Matches bulletin addressees per APRS spec §3.2.16 — `BLN` + a line
  /// number (`0`–`9` or `A`–`Z`), optionally followed by a 1–5 char group
  /// name. Total length capped at 9 by the wire format (matcher further
  /// enforces this via padding/truncation in [AprsEncoder]).
  static final RegExp _bulletinAddresseePattern = RegExp(
    r'^BLN[0-9A-Z][A-Z0-9]{0,5}$',
  );

  // ---------------------------------------------------------------------------
  // Retention sweeper
  // ---------------------------------------------------------------------------

  /// Drop all bulletins whose `lastHeardAt` is older than [retention].
  /// Call from a periodic sweeper (added in PR 5 along with the notification
  /// pipeline).
  Future<void> pruneOlderThan(Duration retention) async {
    final cutoff = _clock().subtract(retention);
    final before = _bulletins.length;
    _bulletins.removeWhere((_, b) => b.lastHeardAt.isBefore(cutoff));
    if (_bulletins.length == before) return;
    await _persist();
    notifyListeners();
  }

  String _key(String source, String addressee) =>
      '${source.toUpperCase()}|${addressee.toUpperCase()}';

  /// Great-circle distance in kilometres between two lat/lon pairs. Flat-
  /// earth approximation would have been enough at hundreds-of-km radii, but
  /// haversine is <10 lines and avoids latitude-dependent error near the
  /// poles or for very large radii.
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

  Future<void> _persist() async {
    final prefs = await _prefs();
    await prefs.setString(
      _keyBulletins,
      jsonEncode(_bulletins.values.map((b) => b.toJson()).toList()),
    );
    await prefs.setInt(_keyNextId, _nextId);
    await prefs.setString(
      keyOutgoingBulletins,
      jsonEncode(_outgoing.values.map((ob) => ob.toJson()).toList()),
    );
    await prefs.setInt(_keyOutgoingNextId, _outgoingNextId);
  }
}
