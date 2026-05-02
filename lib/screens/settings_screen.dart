import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../services/station_settings_service.dart';
import 'settings/category/about_screen.dart';
import 'settings/category/advanced_screen.dart';
import 'settings/category/appearance_screen.dart';
import 'settings/category/beaconing_screen.dart';
import 'settings/category/connections_screen.dart';
import 'settings/category/history_screen.dart';
import 'settings/category/map_screen.dart';
import 'settings/category/my_station_screen.dart';
import 'settings/category/messaging_screen.dart';
import 'settings/category/notifications_screen.dart';
import 'settings/settings_category_list.dart';
import '../ui/utils/platform_route.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Title of the currently-selected category (desktop master/detail only).
  ///
  /// Stored by title rather than by index so that when the visible category
  /// set changes (e.g. Beaconing disappears on Licensed-off), the selection
  /// either follows its category to a new index or — if the category itself
  /// is gone — explicitly falls back to the first visible category. The
  /// previous index-based approach silently shifted the user's selection to
  /// whatever category happened to land at the same slot.
  String? _selectedTitle;

  /// Returns the visible settings categories for the current license state.
  ///
  /// In receive-only mode (unlicensed) the **Beaconing** category is hidden
  /// — every control on that screen produces RF, which the TX gate would
  /// silently drop anyway. Showing it just invites the user to spend time
  /// configuring something that won't fire.
  ///
  /// All other categories stay visible: Connections (still need APRS-IS to
  /// receive), Messaging (the per-channel viewing toggles still apply),
  /// Map / Notifications / History / Appearance / Advanced / About are
  /// orthogonal to TX.
  List<SettingsCategory> _visibleCategories(bool isLicensed) {
    return [
      SettingsCategory(
        title: 'My Station',
        icon: Symbols.person,
        content: const MyStationSettingsContent(),
      ),
      if (isLicensed)
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
        title: 'Messaging',
        icon: Symbols.forum,
        content: const MessagingSettingsContent(),
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
  }

  @override
  Widget build(BuildContext context) {
    final isLicensed = context.select<StationSettingsService, bool>(
      (s) => s.isLicensed,
    );
    final categories = _visibleCategories(isLicensed);
    // Resolve the persisted selection title against the current category set.
    // If the previously-selected category is gone (e.g. user just disabled
    // Licensed and Beaconing was selected) fall back to the first entry —
    // i.e. My Station.
    final resolvedIndex = _selectedTitle == null
        ? 0
        : categories.indexWhere((c) => c.title == _selectedTitle);
    final selectedIndex = resolvedIndex < 0 ? 0 : resolvedIndex;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 840) {
            return _DesktopLayout(
              categories: categories,
              selectedIndex: selectedIndex,
              onSelect: (i) => setState(() {
                _selectedTitle = categories[i].title;
              }),
            );
          }
          return _MobileLayout(categories: categories);
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
