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
    required this.channelEnabled,
    required this.soundEnabled,
    required this.vibrationEnabled,
  });

  final Map<String, bool> channelEnabled;
  final Map<String, bool> soundEnabled;
  final Map<String, bool> vibrationEnabled;

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

  static NotificationPreferences defaults() => NotificationPreferences(
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
    return NotificationPreferences(
      channelEnabled: channelEnabled,
      soundEnabled: soundEnabled,
      vibrationEnabled: vibrationEnabled,
    );
  }

  Future<void> save(SharedPreferences prefs) async {
    for (final e in channelEnabled.entries) {
      await prefs.setBool('notif_channel_${e.key}', e.value);
    }
    for (final e in soundEnabled.entries) {
      await prefs.setBool('notif_sound_${e.key}', e.value);
    }
    for (final e in vibrationEnabled.entries) {
      await prefs.setBool('notif_vibration_${e.key}', e.value);
    }
  }

  NotificationPreferences copyWithChannel(String id, bool enabled) =>
      NotificationPreferences(
        channelEnabled: Map.of(channelEnabled)..[id] = enabled,
        soundEnabled: Map.of(soundEnabled),
        vibrationEnabled: Map.of(vibrationEnabled),
      );

  NotificationPreferences copyWithSound(String id, bool enabled) =>
      NotificationPreferences(
        channelEnabled: Map.of(channelEnabled),
        soundEnabled: Map.of(soundEnabled)..[id] = enabled,
        vibrationEnabled: Map.of(vibrationEnabled),
      );

  NotificationPreferences copyWithVibration(String id, bool enabled) =>
      NotificationPreferences(
        channelEnabled: Map.of(channelEnabled),
        soundEnabled: Map.of(soundEnabled),
        vibrationEnabled: Map.of(vibrationEnabled)..[id] = enabled,
      );
}
