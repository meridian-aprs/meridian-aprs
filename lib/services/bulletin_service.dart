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

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/packet/aprs_packet.dart';
import '../models/bulletin.dart';
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
  }) : _subscriptions = subscriptions,
       _prefsOverride = prefs;

  final BulletinSubscriptionService _subscriptions;
  final SharedPreferences? _prefsOverride;

  static const _keyBulletins = 'bulletins_v1';
  static const _keyNextId = 'bulletins_next_id_v1';
  static const _keyShowBulletins = 'bulletins_show';
  static const _keyRadiusKm = 'bulletins_radius_km';
  static const _keyRetentionHours = 'bulletins_retention_hours';

  /// Allowed radius options (km). `0` is a sentinel for "Map area only" (no
  /// client-side distance filter — the APRS-IS area filter handles it).
  /// The `-1` sentinel means "Global" (no distance filter at all).
  static const List<int> radiusOptionsKm = [0, 100, 500, 1000, -1];

  /// Allowed retention options (hours). Default is 48h (APRSIS32 convention).
  static const List<int> retentionOptionsHours = [24, 48, 72];

  // Keyed by "SOURCE|ADDRESSEE" for stable lookup.
  final Map<String, Bulletin> _bulletins = {};
  int _nextId = 1;

  bool _showBulletins = true;
  int _radiusKm = 500;
  int _retentionHours = 48;

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

  Future<void> load() async {
    final prefs = await _prefs();
    _nextId = prefs.getInt(_keyNextId) ?? 1;
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
        debugPrint('BulletinService: failed to decode: $e');
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

  /// Drop all bulletins whose `lastHeardAt` is older than [retention].
  /// Call from a periodic sweeper (added in PR 5 along with the notification
  /// pipeline).
  Future<void> pruneOlderThan(Duration retention) async {
    final cutoff = DateTime.now().subtract(retention);
    final before = _bulletins.length;
    _bulletins.removeWhere((_, b) => b.lastHeardAt.isBefore(cutoff));
    if (_bulletins.length == before) return;
    await _persist();
    notifyListeners();
  }

  String _key(String source, String addressee) =>
      '${source.toUpperCase()}|${addressee.toUpperCase()}';

  Future<SharedPreferences> _prefs() async =>
      _prefsOverride ?? await SharedPreferences.getInstance();

  Future<void> _persist() async {
    final prefs = await _prefs();
    await prefs.setString(
      _keyBulletins,
      jsonEncode(_bulletins.values.map((b) => b.toJson()).toList()),
    );
    await prefs.setInt(_keyNextId, _nextId);
  }
}
