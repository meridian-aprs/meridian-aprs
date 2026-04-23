import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'settings/category/about_screen.dart';
import 'settings/category/advanced_screen.dart';
import 'settings/category/appearance_screen.dart';
import 'settings/category/beaconing_screen.dart';
import 'settings/category/connections_screen.dart';
import 'settings/category/history_screen.dart';
import 'settings/category/map_screen.dart';
import 'settings/category/my_station_screen.dart';
import 'settings/category/notifications_screen.dart';
import 'settings/settings_category_list.dart';
import '../ui/utils/platform_route.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _selectedIndex = 0;

  static final _categories = <SettingsCategory>[
    SettingsCategory(
      title: 'My Station',
      icon: Symbols.person,
      content: const MyStationSettingsContent(),
    ),
    SettingsCategory(
      title: 'Beaconing',
      icon: Symbols.broadcast_on_personal,
      content: const BeaconingSettingsContent(),
    ),
    SettingsCategory(
      title: 'Connections',
      icon: Symbols.hub,
      content: const ConnectionsSettingsContent(),
    ),
    SettingsCategory(
      title: 'Map',
      icon: Symbols.map,
      content: const MapSettingsContent(),
    ),
    SettingsCategory(
      title: 'Notifications',
      icon: Symbols.notifications,
      content: const NotificationsSettingsContent(),
    ),
    SettingsCategory(
      title: 'History & Storage',
      icon: Symbols.history,
      content: const HistorySettingsContent(),
    ),
    SettingsCategory(
      title: 'Appearance',
      icon: Symbols.palette,
      content: const AppearanceSettingsContent(),
    ),
    SettingsCategory(
      title: 'Advanced',
      icon: Symbols.tune,
      content: const AdvancedSettingsContent(),
      indicatesAdvanced: true,
    ),
    SettingsCategory(
      title: 'About',
      icon: Symbols.info,
      content: const AboutSettingsContent(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 840) {
            return _DesktopLayout(
              categories: _categories,
              selectedIndex: _selectedIndex,
              onSelect: (i) => setState(() => _selectedIndex = i),
            );
          }
          return _MobileLayout(categories: _categories);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mobile layout — hierarchical push-nav
// ---------------------------------------------------------------------------

class _MobileLayout extends StatelessWidget {
  const _MobileLayout({required this.categories});

  final List<SettingsCategory> categories;

  @override
  Widget build(BuildContext context) {
    return SettingsCategoryList(
      categories: categories,
      selectedIndex: -1,
      showChevron: true,
      onCategoryTap: (i) {
        Navigator.push(
          context,
          buildPlatformRoute(
            (_) => _CategoryDetailScreen(
              title: categories[i].title,
              content: categories[i].content,
            ),
          ),
        );
      },
    );
  }
}

class _CategoryDetailScreen extends StatelessWidget {
  const _CategoryDetailScreen({required this.title, required this.content});

  final String title;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: content,
    );
  }
}

// ---------------------------------------------------------------------------
// Desktop layout — master/detail two-pane
// ---------------------------------------------------------------------------

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({
    required this.categories,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<SettingsCategory> categories;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = categories[selectedIndex];

    return Row(
      children: [
        SizedBox(
          width: 280,
          child: Material(
            color: theme.colorScheme.surfaceContainerLow,
            child: SettingsCategoryList(
              categories: categories,
              selectedIndex: selectedIndex,
              showChevron: false,
              onCategoryTap: onSelect,
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Text(selected.title, style: theme.textTheme.titleLarge),
              ),
              const Divider(),
              Expanded(child: selected.content),
            ],
          ),
        ),
      ],
    );
  }
}
