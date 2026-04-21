import 'package:flutter/material.dart';

import 'settings/sections/about_section.dart';
import 'settings/sections/account_section.dart';
import 'settings/sections/acknowledgements_section.dart';
import 'settings/sections/app_color_section.dart';
import 'settings/sections/appearance_section.dart';
import 'settings/sections/aprs_is_filter_section.dart';
import 'settings/sections/beaconing_section.dart';
import 'settings/sections/connection_section.dart';
import 'settings/sections/display_section.dart';
import 'settings/sections/history_section.dart';
import 'settings/sections/map_section.dart';
import 'settings/sections/my_station_section.dart';
import 'settings/sections/notifications_section.dart';

/// Application settings screen.
///
/// The Appearance section (theme mode selection) is fully functional.
/// All other sections are stubbed — they display the correct structure but
/// do not yet wire up to persisted preferences or service config.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sections = [
      const AppearanceSection(),
      const AppColorSection(),
      const MyStationSection(),
      const BeaconingSection(),
      const ConnectionSection(),
      const AprsIsFilterSection(),
      const HistorySection(),
      const MapSection(),
      const DisplaySection(),
      const NotificationsSection(),
      const AccountSection(),
      const AboutSection(),
      const AcknowledgementsSection(),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView.separated(
        itemCount: sections.length,
        separatorBuilder: (context, index) =>
            const Divider(indent: 16, endIndent: 16),
        itemBuilder: (context, index) => sections[index],
      ),
    );
  }
}
