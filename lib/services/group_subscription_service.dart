/// Manages the operator's APRS group subscriptions.
///
/// Seeds three protocol-neutral built-ins on first run (per ADR-056):
///   - `ALL` disabled, notify off, reply `sender`  (broadcast discovery)
///   - `CQ`  enabled,  notify off, reply `sender`  (contact-making)
///   - `QST` enabled,  notify off, reply `sender`  (broadcast discovery)
///
/// Radio-vendor group names (e.g. `YAESU`) are intentionally omitted —
/// Meridian is not a vendor-specific product. Users can add any custom
/// group they want via Settings → Messaging → Groups.
///
/// All state persisted as a JSON blob in SharedPreferences. The drift/SQLite
/// migration is v0.15 scope and will absorb this table.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/group_subscription.dart';

class GroupSubscriptionService extends ChangeNotifier {
  GroupSubscriptionService({SharedPreferences? prefs}) : _prefsOverride = prefs;

  final SharedPreferences? _prefsOverride;

  static const _keySubscriptions = 'group_subscriptions_v1';
  static const _keyNextId = 'group_subscriptions_next_id_v1';
  static const _keySeeded = 'group_subscriptions_seeded_v1';

  final List<GroupSubscription> _subscriptions = [];
  int _nextId = 1;

  /// Unmodifiable read-only list in user-defined order.
  ///
  /// Downstream order-sensitive consumers (the matcher iterates in this order
  /// — first match wins for the `Group` classification) observe whatever
  /// sequence the user has configured in Settings.
  List<GroupSubscription> get subscriptions =>
      List.unmodifiable(_subscriptions);

  /// Only the enabled entries, in order. Use this for the matcher.
  List<GroupSubscription> get enabledSubscriptions =>
      _subscriptions.where((s) => s.enabled).toList(growable: false);

  /// Load persisted state + seed built-ins on first run. Idempotent.
  Future<void> load() async {
    final prefs = await _prefs();
    _nextId = prefs.getInt(_keyNextId) ?? 1;
    final raw = prefs.getString(_keySubscriptions);
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(GroupSubscription.fromJson);
        _subscriptions
          ..clear()
          ..addAll(list);
      } catch (e) {
        debugPrint('GroupSubscriptionService: failed to decode: $e');
      }
    }
    final seeded = prefs.getBool(_keySeeded) ?? false;
    if (!seeded) {
      await _seedBuiltins();
      await prefs.setBool(_keySeeded, true);
    }
    notifyListeners();
  }

  Future<void> _seedBuiltins() async {
    // Only seed names we don't already have (defensive — covers the unlikely
    // case where a user manually created a row named `CQ` before we seeded).
    final existingNames = _subscriptions.map((s) => s.name).toSet();
    final defaults = <_BuiltinDefault>[
      _BuiltinDefault('ALL', enabled: false),
      _BuiltinDefault('CQ', enabled: true),
      _BuiltinDefault('QST', enabled: true),
    ];
    for (final d in defaults) {
      if (existingNames.contains(d.name)) continue;
      _subscriptions.add(
        GroupSubscription(
          id: _nextId++,
          name: d.name,
          enabled: d.enabled,
          notify: false,
          replyMode: ReplyMode.sender,
          isBuiltin: true,
        ),
      );
    }
    await _persist();
  }

  /// Add a custom subscription. Throws [ArgumentError] on invalid name or
  /// duplicate (case-insensitive).
  Future<GroupSubscription> add({
    required String name,
    MatchMode matchMode = MatchMode.prefix,
    ReplyMode replyMode = ReplyMode.group,
    bool notify = true,
    bool enabled = true,
  }) async {
    final normalized = name.trim().toUpperCase();
    if (!GroupSubscription.isValidName(normalized)) {
      throw ArgumentError.value(name, 'name', 'invalid group name');
    }
    if (_subscriptions.any((s) => s.name == normalized)) {
      throw ArgumentError.value(name, 'name', 'duplicate');
    }
    final sub = GroupSubscription(
      id: _nextId++,
      name: normalized,
      matchMode: matchMode,
      replyMode: replyMode,
      notify: notify,
      enabled: enabled,
    );
    _subscriptions.add(sub);
    await _persist();
    notifyListeners();
    return sub;
  }

  /// Update an existing subscription. Built-ins may be updated (enabled,
  /// notify, replyMode, matchMode) but their [name] and [isBuiltin] are
  /// locked.
  Future<void> update(
    int id, {
    MatchMode? matchMode,
    bool? enabled,
    bool? notify,
    ReplyMode? replyMode,
    String? name,
  }) async {
    final idx = _subscriptions.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    final current = _subscriptions[idx];
    String? nextName;
    if (name != null) {
      if (current.isBuiltin) {
        throw StateError('Cannot rename built-in group ${current.name}');
      }
      final normalized = name.trim().toUpperCase();
      if (!GroupSubscription.isValidName(normalized)) {
        throw ArgumentError.value(name, 'name', 'invalid group name');
      }
      if (_subscriptions.any((s) => s.id != id && s.name == normalized)) {
        throw ArgumentError.value(name, 'name', 'duplicate');
      }
      nextName = normalized;
    }
    _subscriptions[idx] = current.copyWith(
      name: nextName,
      matchMode: matchMode,
      enabled: enabled,
      notify: notify,
      replyMode: replyMode,
    );
    await _persist();
    notifyListeners();
  }

  /// Delete a custom subscription. Built-ins cannot be deleted.
  Future<void> delete(int id) async {
    final idx = _subscriptions.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    if (_subscriptions[idx].isBuiltin) {
      throw StateError(
        'Cannot delete built-in group ${_subscriptions[idx].name}',
      );
    }
    _subscriptions.removeAt(idx);
    await _persist();
    notifyListeners();
  }

  /// Reorder the full subscription list. [newOrder] must be a permutation
  /// of the current ids.
  Future<void> reorder(List<int> newOrder) async {
    if (newOrder.length != _subscriptions.length) return;
    final byId = {for (final s in _subscriptions) s.id: s};
    final next = <GroupSubscription>[];
    for (final id in newOrder) {
      final s = byId[id];
      if (s == null) return; // bail — mismatched id set
      next.add(s);
    }
    _subscriptions
      ..clear()
      ..addAll(next);
    await _persist();
    notifyListeners();
  }

  /// Find the subscription matching [addressee] (used by ingestion when a
  /// group classification needs to resolve which subscription was hit —
  /// the matcher already knows, but other callers may not).
  GroupSubscription? findMatching(String addressee) {
    final normalized = addressee.trim().toUpperCase();
    for (final s in enabledSubscriptions) {
      if (s.matches(normalized)) return s;
    }
    return null;
  }

  Future<SharedPreferences> _prefs() async =>
      _prefsOverride ?? await SharedPreferences.getInstance();

  Future<void> _persist() async {
    final prefs = await _prefs();
    await prefs.setString(
      _keySubscriptions,
      jsonEncode(_subscriptions.map((s) => s.toJson()).toList()),
    );
    await prefs.setInt(_keyNextId, _nextId);
  }
}

class _BuiltinDefault {
  _BuiltinDefault(this.name, {required this.enabled});
  final String name;
  final bool enabled;
}
