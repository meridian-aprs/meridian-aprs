library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/callsign/callsign_utils.dart';
import '../../../services/message_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/station_settings_service.dart';
import '../widgets/section_header.dart';

class MessagingSettingsContent extends StatelessWidget {
  const MessagingSettingsContent({super.key});

  @override
  Widget build(BuildContext context) {
    final messageService = context.watch<MessageService>();
    final notifService = context.watch<NotificationService>();
    final station = context.watch<StationSettingsService>();

    final baseCall = stripSsid(station.fullAddress);
    final fullCall = station.fullAddress.isEmpty
        ? 'your callsign'
        : station.fullAddress;
    final prefs = notifService.preferences;

    return ListView(
      children: [
        const SectionHeader('Cross-SSID Messages'),
        SwitchListTile.adaptive(
          title: const Text('Show messages to other SSIDs of my callsign'),
          subtitle: Text(
            "You'll see messages addressed to any SSID of $baseCall, "
            "not just $fullCall. Useful if you run multiple stations. "
            "Replies and acknowledgments still come from $fullCall only.",
          ),
          value: messageService.showOtherSsids,
          onChanged: (v) => messageService.setShowOtherSsids(v),
        ),
        if (messageService.showOtherSsids)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: SwitchListTile.adaptive(
              title: const Text('Notify for messages to other SSIDs'),
              subtitle: Text(
                'Get notifications for messages addressed to any SSID of '
                '$baseCall.',
              ),
              value: prefs.notifyOtherSsids,
              onChanged: (v) => notifService.setNotifyOtherSsids(v),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }
}
