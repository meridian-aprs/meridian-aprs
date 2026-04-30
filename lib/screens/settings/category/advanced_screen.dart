import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../ui/utils/platform_route.dart';
import '../advanced_mode_controller.dart';
import '../ble_diagnostics_screen.dart';

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
        if (advanced.isEnabled) ...[
          const Divider(),
          ListTile(
            leading: const Icon(Symbols.bluetooth_searching),
            title: const Text('BLE Diagnostics'),
            subtitle: const Text(
              'Live event log for debugging BLE TNC drops in the background.',
            ),
            trailing: const Icon(Symbols.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(buildPlatformRoute((_) => const BleDiagnosticsScreen())),
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}
