import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import 'advanced_mode_controller.dart';

class SettingsCategoryList extends StatelessWidget {
  const SettingsCategoryList({
    super.key,
    required this.categories,
    required this.selectedIndex,
    required this.showChevron,
    required this.onCategoryTap,
  });

  final List<SettingsCategory> categories;
  final int selectedIndex;
  final bool showChevron;
  final ValueChanged<int> onCategoryTap;

  @override
  Widget build(BuildContext context) {
    final advanced = context.watch<AdvancedModeController>();

    return ListView(
      children: [
        SwitchListTile.adaptive(
          title: const Text('Advanced User Mode'),
          subtitle: const Text('Show advanced settings throughout the app.'),
          secondary: const Icon(Symbols.tune),
          value: advanced.isEnabled,
          onChanged: (v) =>
              context.read<AdvancedModeController>().setEnabled(v),
        ),
        const Divider(indent: 16, endIndent: 16),
        for (var i = 0; i < categories.length; i++)
          ListTile(
            leading: Icon(categories[i].icon),
            title: Text(categories[i].title),
            selected: i == selectedIndex,
            trailing: showChevron ? const Icon(Icons.chevron_right) : null,
            onTap: () => onCategoryTap(i),
          ),
      ],
    );
  }
}

class SettingsCategory {
  const SettingsCategory({
    required this.title,
    required this.icon,
    required this.content,
  });

  final String title;
  final IconData icon;
  final Widget content;
}
