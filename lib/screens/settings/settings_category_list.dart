import 'package:flutter/material.dart';
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
    final theme = Theme.of(context);

    return ListView(
      children: [
        for (var i = 0; i < categories.length; i++)
          ListTile(
            leading: Icon(
              categories[i].icon,
              color: (categories[i].indicatesAdvanced && advanced.isEnabled)
                  ? theme.colorScheme.primary
                  : null,
            ),
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
    this.indicatesAdvanced = false,
  });

  final String title;
  final IconData icon;
  final Widget content;
  final bool indicatesAdvanced;
}
