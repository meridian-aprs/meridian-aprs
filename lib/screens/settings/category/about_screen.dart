import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../ui/widgets/meridian_wordmark.dart';
import '../widgets/section_header.dart';

class AboutSettingsContent extends StatelessWidget {
  const AboutSettingsContent({super.key});

  static const kVersion = '0.1.0';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        const SectionHeader('About'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Card.filled(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Center(
                child: Column(
                  children: [
                    const MeridianWordmark.horizontal(height: 64),
                    const SizedBox(height: 16),
                    const SizedBox(height: 4),
                    Text(
                      'Version $kVersion',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'APRS for the Modern Ham',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '© 2026 Eric Pasch  ·  GPL v3',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Inter typeface by Rasmus Andersson (SIL OFL)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Symbols.lock_outline),
          title: const Text('Credential storage'),
          subtitle: const Text(
            'Passcode stored in platform secure storage (Keychain on iOS/macOS, EncryptedSharedPreferences on Android, Credential Manager on Windows, libsecret on Linux). Web: browser-encrypted IndexedDB — not hardware-backed.',
          ),
        ),
        ListTile(
          leading: const Icon(Icons.devices),
          title: const Text('Device identification data'),
          subtitle: const Text(
            '© Heikki Hannikainen (OH7LZB) and contributors · CC BY-SA 2.0',
          ),
          trailing: const Icon(Symbols.open_in_new, size: 16),
          onTap: () => _launchUri(
            Uri.parse('https://github.com/aprsorg/aprs-deviceid'),
            context,
          ),
        ),
        ListTile(
          leading: const Icon(Symbols.code),
          title: const Text('GitHub'),
          subtitle: const Text('github.com/epasch/meridian-aprs'),
          trailing: const Icon(Symbols.open_in_new, size: 16),
          onTap: () => _launchUri(
            Uri.parse('https://github.com/epasch/meridian-aprs'),
            context,
          ),
        ),
        ListTile(
          leading: const Icon(Symbols.language),
          title: const Text('Website'),
          subtitle: const Text('meridianaprs.com'),
          trailing: const Icon(Symbols.open_in_new, size: 16),
          onTap: () =>
              _launchUri(Uri.parse('https://meridianaprs.com'), context),
        ),
        const SectionHeader('Acknowledgements'),
        ListTile(
          title: const Text('APRS Symbol Graphics'),
          subtitle: const Text(
            'aprs.fi symbol set by Heikki Hannikainen OH7LZB',
          ),
          trailing: const Icon(Symbols.open_in_new, size: 16),
          onTap: () => _launchUri(
            Uri.parse('https://github.com/hessu/aprs-symbols'),
            context,
          ),
        ),
        ListTile(
          title: const Text('Map Library'),
          subtitle: const Text('flutter_map by Luka S and contributors'),
          trailing: const Icon(Symbols.open_in_new, size: 16),
          onTap: () => _launchUri(
            Uri.parse('https://github.com/fleaflet/flutter_map'),
            context,
          ),
        ),
        ListTile(
          title: const Text('Map Data'),
          subtitle: const Text('© OpenStreetMap contributors'),
          trailing: const Icon(Symbols.open_in_new, size: 16),
          onTap: () => _launchUri(
            Uri.parse('https://www.openstreetmap.org/copyright'),
            context,
          ),
        ),
        ListTile(
          title: const Text('Map Tiles'),
          subtitle: const Text('Stadia Maps'),
          trailing: const Icon(Symbols.open_in_new, size: 16),
          onTap: () => _launchUri(Uri.parse('https://stadiamaps.com'), context),
        ),
        ListTile(
          title: const Text('Open Source Licenses'),
          trailing: const Icon(Symbols.chevron_right),
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'Meridian APRS',
            applicationVersion: kVersion,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

Future<void> _launchUri(Uri uri, BuildContext context) async {
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open ${uri.host}')));
    }
  }
}
