import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../widgets/section_header.dart';

class DisplaySection extends StatelessWidget {
  const DisplaySection({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader('Display'),
        ListTile(
          title: Text('Station timeout'),
          subtitle: Text('Hide stations not heard for this long'),
          trailing: Icon(Symbols.chevron_right),
        ),
        ListTile(
          title: Text('Trail length'),
          subtitle: Text('Number of position points to show per station'),
          trailing: Icon(Symbols.chevron_right),
        ),
      ],
    );
  }
}
