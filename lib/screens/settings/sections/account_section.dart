import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../widgets/section_header.dart';

class AccountSection extends StatelessWidget {
  const AccountSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Account'),
        ListTile(
          title: const Text('Sign in'),
          subtitle: const Text('Sign in to sync preferences across devices.'),
          trailing: Icon(
            Symbols.chevron_right,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          enabled: false, // Stub — backend not yet implemented.
        ),
      ],
    );
  }
}
