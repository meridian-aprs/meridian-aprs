import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../advanced_mode_controller.dart';

class AdvancedSettingsContent extends StatelessWidget {
  const AdvancedSettingsContent({super.key});

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
        const SizedBox(height: 16),
      ],
    );
  }
}
