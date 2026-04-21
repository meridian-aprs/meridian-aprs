import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/section_header.dart';
import 'about_section.dart';

class AcknowledgementsSection extends StatelessWidget {
  const AcknowledgementsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            applicationVersion: AboutSection.kVersion,
          ),
        ),
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
