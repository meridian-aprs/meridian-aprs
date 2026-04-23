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

    return ListView(
      children: [
        for (var i = 0; i < categories.length; i++)
          ListTile(
            leading: Icon(categories[i].icon),
            title: Text(categories[i].title),
            selected: i == selectedIndex,
            trailing: _buildTrailing(
              context,
              cat: categories[i],
              advancedOn: advanced.isEnabled,
            ),
            onTap: () => onCategoryTap(i),
          ),
      ],
    );
  }

  Widget? _buildTrailing(
    BuildContext context, {
    required SettingsCategory cat,
    required bool advancedOn,
  }) {
    final showPill = cat.indicatesAdvanced && advancedOn;
    if (!showChevron && !showPill) return null;
    if (!showChevron) return const _OnPill();
    if (!showPill) return const Icon(Icons.chevron_right);
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [_OnPill(), SizedBox(width: 8), Icon(Icons.chevron_right)],
    );
  }
}

class _OnPill extends StatelessWidget {
  const _OnPill();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'On',
        style: ts.labelSmall?.copyWith(
          color: cs.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
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
