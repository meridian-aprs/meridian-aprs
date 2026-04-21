import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/notification_preferences.dart';
import '../../../services/notification_service.dart';
import '../widgets/section_header.dart';

class NotificationsSection extends StatelessWidget {
  const NotificationsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final notif = context.watch<NotificationService>();
    final prefs = notif.preferences;
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Notifications'),
        SwitchListTile.adaptive(
          title: const Text('Notifications enabled'),
          subtitle: Text(
            prefs.optedIn
                ? 'Meridian will notify you when a message arrives.'
                : 'Notifications are disabled. Enable to get message alerts.',
          ),
          value: prefs.optedIn,
          onChanged: (v) async {
            if (v) {
              await notif.requestNotificationPermissions();
            } else {
              await notif.setOptedIn(false);
            }
          },
        ),
        if (prefs.optedIn)
          _NotificationChannelTile(
            channelId: NotificationChannels.messages,
            label: 'Messages',
            description: 'Notify when a message addressed to you arrives.',
            prefs: prefs,
            notif: notif,
            isMobile: isMobile,
          ),
      ],
    );
  }
}

class _NotificationChannelTile extends StatelessWidget {
  const _NotificationChannelTile({
    required this.channelId,
    required this.label,
    required this.description,
    required this.prefs,
    required this.notif,
    required this.isMobile,
  });

  final String channelId;
  final String label;
  final String description;
  final NotificationPreferences prefs;
  final NotificationService notif;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final enabled = prefs.isChannelEnabled(channelId);
    return Column(
      children: [
        SwitchListTile.adaptive(
          title: Text(label),
          subtitle: Text(description),
          value: enabled,
          onChanged: (v) => notif.setChannelEnabled(channelId, v),
        ),
        if (isMobile) ...[
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: SwitchListTile.adaptive(
              title: const Text('Sound'),
              value: prefs.isSoundEnabled(channelId),
              onChanged: enabled
                  ? (v) => notif.setSoundEnabled(channelId, v)
                  : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: SwitchListTile.adaptive(
              title: const Text('Vibration'),
              value: prefs.isVibrationEnabled(channelId),
              onChanged: enabled
                  ? (v) => notif.setVibrationEnabled(channelId, v)
                  : null,
            ),
          ),
        ],
      ],
    );
  }
}
