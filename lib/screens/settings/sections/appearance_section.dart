import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../theme/theme_controller.dart';
import '../widgets/section_header.dart';

class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ThemeController>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Appearance'),
        ListTile(
          title: const Text('Theme'),
          subtitle: const Text('Choose light, dark, or follow the system.'),
          trailing: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Symbols.light_mode),
                label: Text('Light'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Symbols.dark_mode),
                label: Text('Dark'),
              ),
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Symbols.brightness_auto),
                label: Text('Auto'),
              ),
            ],
            selected: {controller.themeMode},
            onSelectionChanged: (modes) {
              if (modes.isNotEmpty) {
                context.read<ThemeController>().setThemeMode(modes.first);
              }
            },
          ),
        ),
      ],
    );
  }
}
