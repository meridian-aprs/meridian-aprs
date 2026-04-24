library;

import 'package:shared_preferences/shared_preferences.dart';

/// Notification channel IDs — extensible taxonomy established in v0.11.
abstract final class NotificationChannels {
  static const messages = 'messages';
  static const alerts = 'alerts';
  static const nearby = 'nearby';
  static const system = 'system';

  static const all = [messages, alerts, nearby, system];
}

/// Per-channel notification preferences persisted to SharedPreferences.
class NotificationPreferences {
  const NotificationPreferences({
    required this.optedIn,
    required this.channelEnabled,
    required this.soundEnabled,
    required this.vibrationEnabled,
    this.notifyOtherSsids = false,
    this.notifyGroups = true,
    this.notifyBulletins = false,
  });

  /// Global opt-in flag — false means no notifications are dispatched even if
  /// OS permission is granted. Set to true by onboarding "Enable" or Settings
  /// toggle. Defaults to true for pre-v0.12 installs (migration in
  /// NotificationService.initialize).
  final bool optedIn;

  final Map<String, bool> channelEnabled;
  final Map<String, bool> soundEnabled;
  final Map<String, bool> vibrationEnabled;

  /// When true, notifications are also dispatched for messages addressed to a
  /// different SSID of the operator's callsign (cross-SSID capture). Defaults
  /// to false — opt-in only.
  final bool notifyOtherSsids;

  /// Master toggle for group-message notifications (v0.17). Per-group
  /// `notify` on [GroupSubscription] further gates individual groups.
  /// Defaults to true so users see a group they intentionally subscribed
  /// to, without an extra Settings visit.
  final bool notifyGroups;

  /// Master toggle for bulletin notifications (v0.17). Per-group
  /// `notify` on [BulletinSubscription] further gates individual named
  /// groups. Defaults to false — bulletins are broadcast-noisy by nature.
  final bool notifyBulletins;

  static const _keyNotifyOtherSsids = 'notif_notify_other_ssids';
  static const _keyNotifyGroups = 'notif_notify_groups';
  static const _keyNotifyBulletins = 'notif_notify_bulletins';

  // Default sound/vibration: on for messages+alerts, off for nearby+system.
  static const _defaultSound = {
    NotificationChannels.messages: true,
    NotificationChannels.alerts: true,
    NotificationChannels.nearby: false,
    NotificationChannels.system: false,
  };

  static const _defaultVibration = {
    NotificationChannels.messages: true,
    NotificationChannels.alerts: true,
    NotificationChannels.nearby: false,
    NotificationChannels.system: false,
  };

  // notifyOtherSsids uses its constructor default (false) and is not passed
  // explicitly in defaults() — intentional.
  static NotificationPreferences defaults({bool optedIn = false}) =>
      NotificationPreferences(
        optedIn: optedIn,
        channelEnabled: {for (final c in NotificationChannels.all) c: true},
        soundEnabled: Map.of(_defaultSound),
        vibrationEnabled: Map.of(_defaultVibration),
      );

  bool isChannelEnabled(String id) => channelEnabled[id] ?? true;

  bool isSoundEnabled(String id) =>
      soundEnabled[id] ?? (_defaultSound[id] ?? false);

  bool isVibrationEnabled(String id) =>
      vibrationEnabled[id] ?? (_defaultVibration[id] ?? false);

  static Future<NotificationPreferences> load(SharedPreferences prefs) async {
    // null means key absent (first run or pre-v0.12 upgrade); migration in
    // NotificationService.initialize() sets true for existing opted-in users.
    final optedIn = prefs.getBool('notif_opted_in') ?? false;
    final channelEnabled = <String, bool>{};
    final soundEnabled = <String, bool>{};
    final vibrationEnabled = <String, bool>{};
    for (final ch in NotificationChannels.all) {
      channelEnabled[ch] = prefs.getBool('notif_channel_$ch') ?? true;
      soundEnabled[ch] =
          prefs.getBool('notif_sound_$ch') ?? (_defaultSound[ch] ?? false);
      vibrationEnabled[ch] =
          prefs.getBool('notif_vibration_$ch') ??
          (_defaultVibration[ch] ?? false);
    }
    final notifyOtherSsids = prefs.getBool(_keyNotifyOtherSsids) ?? false;
    final notifyGroups = prefs.getBool(_keyNotifyGroups) ?? true;
    final notifyBulletins = prefs.getBool(_keyNotifyBulletins) ?? false;
    return NotificationPreferences(
      optedIn: optedIn,
      channelEnabled: channelEnabled,
      soundEnabled: soundEnabled,
      vibrationEnabled: vibrationEnabled,
      notifyOtherSsids: notifyOtherSsids,
      notifyGroups: notifyGroups,
      notifyBulletins: notifyBulletins,
    );
  }

  Future<void> save(SharedPreferences prefs) async {
    await prefs.setBool('notif_opted_in', optedIn);
    for (final e in channelEnabled.entries) {
      await prefs.setBool('notif_channel_${e.key}', e.value);
    }
    for (final e in soundEnabled.entries) {
      await prefs.setBool('notif_sound_${e.key}', e.value);
    }
    for (final e in vibrationEnabled.entries) {
      await prefs.setBool('notif_vibration_${e.key}', e.value);
    }
    await prefs.setBool(_keyNotifyOtherSsids, notifyOtherSsids);
    await prefs.setBool(_keyNotifyGroups, notifyGroups);
    await prefs.setBool(_keyNotifyBulletins, notifyBulletins);
  }

  NotificationPreferences copyWithOptedIn(bool value) =>
      NotificationPreferences(
        optedIn: value,
        channelEnabled: Map.of(channelEnabled),
        soundEnabled: Map.of(soundEnabled),
        vibrationEnabled: Map.of(vibrationEnabled),
        notifyOtherSsids: notifyOtherSsids,
        notifyGroups: notifyGroups,
        notifyBulletins: notifyBulletins,
      );

  NotificationPreferences copyWithChannel(String id, bool enabled) =>
      NotificationPreferences(
        optedIn: optedIn,
        channelEnabled: Map.of(channelEnabled)..[id] = enabled,
        soundEnabled: Map.of(soundEnabled),
        vibrationEnabled: Map.of(vibrationEnabled),
        notifyOtherSsids: notifyOtherSsids,
        notifyGroups: notifyGroups,
        notifyBulletins: notifyBulletins,
      );

  NotificationPreferences copyWithSound(String id, bool enabled) =>
      NotificationPreferences(
        optedIn: optedIn,
        channelEnabled: Map.of(channelEnabled),
        soundEnabled: Map.of(soundEnabled)..[id] = enabled,
        vibrationEnabled: Map.of(vibrationEnabled),
        notifyOtherSsids: notifyOtherSsids,
        notifyGroups: notifyGroups,
        notifyBulletins: notifyBulletins,
      );

  NotificationPreferences copyWithVibration(String id, bool enabled) =>
      NotificationPreferences(
        optedIn: optedIn,
        channelEnabled: Map.of(channelEnabled),
        soundEnabled: Map.of(soundEnabled),
        vibrationEnabled: Map.of(vibrationEnabled)..[id] = enabled,
        notifyOtherSsids: notifyOtherSsids,
        notifyGroups: notifyGroups,
        notifyBulletins: notifyBulletins,
      );

  NotificationPreferences copyWithNotifyOtherSsids(bool v) =>
      NotificationPreferences(
        optedIn: optedIn,
        channelEnabled: Map.of(channelEnabled),
        soundEnabled: Map.of(soundEnabled),
        vibrationEnabled: Map.of(vibrationEnabled),
        notifyOtherSsids: v,
        notifyGroups: notifyGroups,
        notifyBulletins: notifyBulletins,
      );

  NotificationPreferences copyWithNotifyGroups(bool v) =>
      NotificationPreferences(
        optedIn: optedIn,
        channelEnabled: Map.of(channelEnabled),
        soundEnabled: Map.of(soundEnabled),
        vibrationEnabled: Map.of(vibrationEnabled),
        notifyOtherSsids: notifyOtherSsids,
        notifyGroups: v,
        notifyBulletins: notifyBulletins,
      );

  NotificationPreferences copyWithNotifyBulletins(bool v) =>
      NotificationPreferences(
        optedIn: optedIn,
        channelEnabled: Map.of(channelEnabled),
        soundEnabled: Map.of(soundEnabled),
        vibrationEnabled: Map.of(vibrationEnabled),
        notifyOtherSsids: notifyOtherSsids,
        notifyGroups: notifyGroups,
        notifyBulletins: v,
      );
}
