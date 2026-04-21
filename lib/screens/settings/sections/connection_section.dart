import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../widgets/section_header.dart';

class ConnectionSection extends StatelessWidget {
  const ConnectionSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader('Connection'),
        ListTile(
          title: Text('Default server'),
          subtitle: Text('rotate.aprs2.net:14580'),
          trailing: Icon(Symbols.chevron_right),
        ),
        ListTile(
          title: Text('Filter'),
          subtitle: Text('Range filter around current position'),
          trailing: Icon(Symbols.chevron_right),
        ),
      ],
    );
  }
}
