import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/transport/tnc_preset.dart';
import '../services/tnc_service.dart';
import '../ui/theme/theme_provider.dart';

/// Application settings screen.
///
/// The Appearance section (theme mode selection) is fully functional.
/// All other sections are stubbed — they display the correct structure but
/// do not yet wire up to persisted preferences or service config.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView.separated(
        itemCount: 9,
        separatorBuilder: (context, index) =>
            const Divider(indent: 16, endIndent: 16),
        itemBuilder: (context, index) => [
          const _AppearanceSection(),
          const _MyStationSection(),
          const _BeaconingSection(),
          const _ConnectionSection(),
          const _TncSection(),
          const _DisplaySection(),
          const _NotificationsSection(),
          const _AccountSection(),
          const _AboutSection(),
        ][index],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header helper
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Appearance
// ---------------------------------------------------------------------------

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('Appearance'),
        ListTile(
          title: const Text('Theme'),
          subtitle: const Text('Choose light, dark, or follow the system.'),
          trailing: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode),
                label: Text('Light'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode),
                label: Text('Dark'),
              ),
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto),
                label: Text('Auto'),
              ),
            ],
            selected: {themeProvider.themeMode},
            onSelectionChanged: (modes) {
              if (modes.isNotEmpty) {
                context.read<ThemeProvider>().setThemeMode(modes.first);
              }
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// My Station
// ---------------------------------------------------------------------------

class _MyStationSection extends StatelessWidget {
  const _MyStationSection();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('My Station'),
        ListTile(title: Text('Callsign'), trailing: Icon(Icons.chevron_right)),
        ListTile(title: Text('SSID'), trailing: Icon(Icons.chevron_right)),
        ListTile(title: Text('Symbol'), trailing: Icon(Icons.chevron_right)),
        ListTile(title: Text('Comment'), trailing: Icon(Icons.chevron_right)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Beaconing
// ---------------------------------------------------------------------------

class _BeaconingSection extends StatelessWidget {
  const _BeaconingSection();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('Beaconing'),
        SwitchListTile(
          title: Text('Smart beaconing'),
          subtitle: Text(
            'Adjusts beacon rate based on speed and heading change.',
          ),
          value: false,
          onChanged: null, // Stub — not yet functional.
        ),
        ListTile(title: Text('Interval'), trailing: Icon(Icons.chevron_right)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Connection
// ---------------------------------------------------------------------------

class _ConnectionSection extends StatelessWidget {
  const _ConnectionSection();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('Connection'),
        ListTile(
          title: Text('Default server'),
          subtitle: Text('rotate.aprs2.net:14580'),
          trailing: Icon(Icons.chevron_right),
        ),
        ListTile(
          title: Text('Filter'),
          subtitle: Text('Range filter around current position'),
          trailing: Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// TNC
// ---------------------------------------------------------------------------

class _TncSection extends StatelessWidget {
  const _TncSection();

  @override
  Widget build(BuildContext context) {
    final tncService = context.watch<TncService>();
    final config = tncService.activeConfig;

    // Find preset name from presetId, if available.
    String presetName = 'Custom';
    if (config?.presetId != null) {
      final match = TncPreset.all.where((p) => p.id == config!.presetId);
      if (match.isNotEmpty) presetName = match.first.displayName;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('TNC'),
        if (config == null)
          const ListTile(
            title: Text('No TNC configured'),
            subtitle: Text(
              'Use the connection sheet to configure and connect a TNC.',
            ),
          )
        else ...[
          ListTile(
            title: const Text('Preset'),
            subtitle: Text(presetName),
          ),
          ListTile(
            title: const Text('Port'),
            subtitle: Text(config.port),
          ),
          ListTile(
            title: const Text('Baud rate'),
            subtitle: Text('${config.baudRate}'),
          ),
          ListTile(
            title: const Text('Data bits'),
            subtitle: Text('${config.dataBits}'),
          ),
          ListTile(
            title: const Text('Stop bits'),
            subtitle: Text('${config.stopBits}'),
          ),
          ListTile(
            title: const Text('Parity'),
            subtitle: Text(config.parity),
          ),
          SwitchListTile(
            title: const Text('Hardware flow control'),
            value: config.hardwareFlowControl,
            onChanged: null, // Read-only in v0.3 — editing via connection sheet.
          ),
          ExpansionTile(
            title: const Text('Advanced KISS parameters'),
            initiallyExpanded: false,
            children: [
              ListTile(
                title: const Text('TX delay (ms)'),
                subtitle: Text('${config.kissTxDelayMs}'),
              ),
              ListTile(
                title: const Text('Persistence (0–255)'),
                subtitle: Text('${config.kissPersistence}'),
              ),
              ListTile(
                title: const Text('Slot time (ms)'),
                subtitle: Text('${config.kissSlotTimeMs}'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Display
// ---------------------------------------------------------------------------

class _DisplaySection extends StatelessWidget {
  const _DisplaySection();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('Display'),
        ListTile(
          title: Text('Station timeout'),
          subtitle: Text('Hide stations not heard for this long'),
          trailing: Icon(Icons.chevron_right),
        ),
        ListTile(
          title: Text('Trail length'),
          subtitle: Text('Number of position points to show per station'),
          trailing: Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------------

class _NotificationsSection extends StatelessWidget {
  const _NotificationsSection();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('Notifications'),
        SwitchListTile(
          title: Text('Message alerts'),
          subtitle: Text('Notify when a message addressed to you arrives.'),
          value: false,
          onChanged: null, // Stub — not yet functional.
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Account
// ---------------------------------------------------------------------------

class _AccountSection extends StatelessWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('Account'),
        ListTile(
          title: const Text('Sign in'),
          subtitle: const Text('Sign in to sync preferences across devices.'),
          trailing: Icon(
            Icons.arrow_forward_ios,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          enabled: false, // Stub — backend not yet implemented.
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// About
// ---------------------------------------------------------------------------

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('About'),
        ListTile(title: Text('Version'), trailing: Text('0.1.0')),
        ListTile(
          title: Text('GitHub'),
          subtitle: Text('https://github.com/epasch/meridian-aprs'),
          trailing: Icon(Icons.open_in_new, size: 16),
        ),
      ],
    );
  }
}
