/// Advanced-mode path and blocklist settings for v0.17 messaging.
///
/// Owns three preferences that only appear in the Settings UI when Advanced
/// Mode is enabled (ADR-053):
///
///   - `groupMessagePath` — RF digipeater path for outgoing group messages.
///     Default is empty, which means "use the same path the beacon encoder
///     uses" (today hardcoded to `WIDE1-1,WIDE2-1` in [Ax25Encoder]).
///   - `bulletinPath` — RF digipeater path for outgoing bulletins. Default
///     `WIDE2-2` per traditional APRS bulletin convention.
///   - `mutedBulletinSources` — callsigns whose bulletins are suppressed on
///     the Bulletins tab regardless of scope.
///
/// Consumed by PR 4's send path (`BulletinScheduler`, group send). PR 2
/// wires UI + persistence only.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MessagingSettingsService extends ChangeNotifier {
  MessagingSettingsService({SharedPreferences? prefs}) : _prefsOverride = prefs;

  final SharedPreferences? _prefsOverride;

  static const _keyGroupMessagePath = 'messaging_group_message_path';
  static const _keyBulletinPath = 'messaging_bulletin_path';
  static const _keyMutedBulletinSources = 'messaging_muted_bulletin_sources';

  /// Default bulletin path per spec §3.
  static const defaultBulletinPath = 'WIDE2-2';

  /// Resolved text for the "uses beacon path" default when [groupMessagePath]
  /// is empty. Today this is hardcoded in [Ax25Encoder.buildAprsFrame]; when a
  /// configurable beacon path is introduced this string becomes dynamic.
  static const resolvedDefaultGroupMessagePath = 'WIDE1-1,WIDE2-1';

  String _groupMessagePath = '';
  String _bulletinPath = defaultBulletinPath;
  Set<String> _mutedBulletinSources = {};

  /// Empty string means "same as beacon path" — see
  /// [resolvedDefaultGroupMessagePath].
  String get groupMessagePath => _groupMessagePath;

  String get bulletinPath => _bulletinPath;

  Set<String> get mutedBulletinSources =>
      Set.unmodifiable(_mutedBulletinSources);

  /// Effective path string used by the TX layer for group messages.
  String get effectiveGroupMessagePath => _groupMessagePath.isEmpty
      ? resolvedDefaultGroupMessagePath
      : _groupMessagePath;

  Future<void> load() async {
    final prefs = await _prefs();
    _groupMessagePath = prefs.getString(_keyGroupMessagePath) ?? '';
    _bulletinPath = prefs.getString(_keyBulletinPath) ?? defaultBulletinPath;
    final raw = prefs.getString(_keyMutedBulletinSources);
    if (raw != null) {
      try {
        _mutedBulletinSources =
            ((jsonDecode(raw) as List<dynamic>).cast<String>())
                .map((c) => c.toUpperCase())
                .toSet();
      } catch (_) {
        _mutedBulletinSources = {};
      }
    }
    notifyListeners();
  }

  Future<void> setGroupMessagePath(String value) async {
    final v = value.trim();
    if (_groupMessagePath == v) return;
    _groupMessagePath = v;
    final prefs = await _prefs();
    if (v.isEmpty) {
      await prefs.remove(_keyGroupMessagePath);
    } else {
      await prefs.setString(_keyGroupMessagePath, v);
    }
    notifyListeners();
  }

  Future<void> setBulletinPath(String value) async {
    final v = value.trim();
    if (v.isEmpty) {
      // Reject empty — bulletins must have a path. Revert to default instead
      // of silently failing (caller should pass explicit default to reset).
      throw ArgumentError.value(value, 'bulletinPath', 'must not be empty');
    }
    if (_bulletinPath == v) return;
    _bulletinPath = v;
    final prefs = await _prefs();
    await prefs.setString(_keyBulletinPath, v);
    notifyListeners();
  }

  Future<void> addMutedBulletinSource(String callsign) async {
    final normalized = callsign.trim().toUpperCase();
    if (normalized.isEmpty) return;
    if (_mutedBulletinSources.contains(normalized)) return;
    _mutedBulletinSources = {..._mutedBulletinSources, normalized};
    await _persistMutedSources();
    notifyListeners();
  }

  Future<void> removeMutedBulletinSource(String callsign) async {
    final normalized = callsign.trim().toUpperCase();
    if (!_mutedBulletinSources.contains(normalized)) return;
    _mutedBulletinSources = {..._mutedBulletinSources}..remove(normalized);
    await _persistMutedSources();
    notifyListeners();
  }

  Future<void> _persistMutedSources() async {
    final prefs = await _prefs();
    await prefs.setString(
      _keyMutedBulletinSources,
      jsonEncode(_mutedBulletinSources.toList()),
    );
  }

  Future<SharedPreferences> _prefs() async =>
      _prefsOverride ?? await SharedPreferences.getInstance();
}
