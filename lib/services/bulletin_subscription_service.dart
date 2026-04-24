/// Manages the operator's named-bulletin-group subscriptions (`BLNxWX`, etc.).
///
/// No defaults seeded — the operator explicitly subscribes to groups they
/// want (per spec §5.2). General `BLN0`–`BLN9` bulletins are governed by
/// distance/radius, not by subscriptions; that logic lives in [BulletinService].
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/bulletin_subscription.dart';

class BulletinSubscriptionService extends ChangeNotifier {
  BulletinSubscriptionService({SharedPreferences? prefs})
    : _prefsOverride = prefs;

  final SharedPreferences? _prefsOverride;

  static const _keySubscriptions = 'bulletin_subscriptions_v1';
  static const _keyNextId = 'bulletin_subscriptions_next_id_v1';

  final List<BulletinSubscription> _subscriptions = [];
  int _nextId = 1;

  List<BulletinSubscription> get subscriptions =>
      List.unmodifiable(_subscriptions);

  /// The set of subscribed group names (uppercased). Used by
  /// [BulletinService] to decide whether an incoming `BLNxNAME` is kept.
  Set<String> get subscribedGroupNames =>
      _subscriptions.map((s) => s.groupName).toSet();

  Future<void> load() async {
    final prefs = await _prefs();
    _nextId = prefs.getInt(_keyNextId) ?? 1;
    final raw = prefs.getString(_keySubscriptions);
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(BulletinSubscription.fromJson);
        _subscriptions
          ..clear()
          ..addAll(list);
      } catch (e) {
        debugPrint('BulletinSubscriptionService: failed to decode: $e');
      }
    }
    notifyListeners();
  }

  Future<BulletinSubscription> add({
    required String groupName,
    bool notify = true,
  }) async {
    final normalized = groupName.trim().toUpperCase();
    if (!BulletinSubscription.isValidName(normalized)) {
      throw ArgumentError.value(groupName, 'groupName', 'invalid');
    }
    if (_subscriptions.any((s) => s.groupName == normalized)) {
      throw ArgumentError.value(groupName, 'groupName', 'duplicate');
    }
    final sub = BulletinSubscription(
      id: _nextId++,
      groupName: normalized,
      notify: notify,
    );
    _subscriptions.add(sub);
    await _persist();
    notifyListeners();
    return sub;
  }

  Future<void> update(int id, {bool? notify}) async {
    final idx = _subscriptions.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    _subscriptions[idx] = _subscriptions[idx].copyWith(notify: notify);
    await _persist();
    notifyListeners();
  }

  Future<void> delete(int id) async {
    final removed = _subscriptions.length;
    _subscriptions.removeWhere((s) => s.id == id);
    if (_subscriptions.length == removed) return;
    await _persist();
    notifyListeners();
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
