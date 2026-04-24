/// Read-only detail view for a single bulletin (spec §4.4).
///
/// No inline reply — bulletins are one-way. Offers a "Message sender"
/// action that opens a direct conversation with the source callsign.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/bulletin.dart';
import '../services/bulletin_service.dart';
import '../ui/utils/platform_route.dart';
import 'message_thread_screen.dart';

class BulletinDetailScreen extends StatelessWidget {
  const BulletinDetailScreen({super.key, required this.bulletinId});

  final int bulletinId;

  Bulletin? _lookup(BulletinService service) {
    for (final b in service.bulletins) {
      if (b.id == bulletinId) return b;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bulletins = context.watch<BulletinService>();
    final bulletin = _lookup(bulletins);
    final theme = Theme.of(context);

    if (bulletin == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Bulletin')),
        body: const Center(
          child: Text('This bulletin is no longer available.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(bulletin.addressee),
        actions: [
          IconButton(
            icon: const Icon(Symbols.mail),
            tooltip: 'Message sender',
            onPressed: () {
              Navigator.push(
                context,
                buildPlatformRoute(
                  (_) => MessageThreadScreen(
                    peerCallsign: bulletin.sourceCallsign,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Icon(Symbols.campaign, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(bulletin.addressee, style: theme.textTheme.titleLarge),
              const Spacer(),
              for (final t in bulletin.transports)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: _TransportBadge(transport: t),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'From ${bulletin.sourceCallsign}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          SelectableText(bulletin.body, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 24),
          const Divider(),
          _InfoRow(
            icon: Symbols.schedule,
            label: 'First heard',
            value: _formatAbsolute(bulletin.firstHeardAt),
          ),
          _InfoRow(
            icon: Symbols.update,
            label: 'Last heard',
            value: _formatAbsolute(bulletin.lastHeardAt),
          ),
          _InfoRow(
            icon: Symbols.numbers,
            label: 'Total receipts',
            value: bulletin.heardCount.toString(),
          ),
          _InfoRow(
            icon: Symbols.category,
            label: 'Category',
            value: switch (bulletin.category) {
              BulletinCategory.general => 'General (BLN0–BLN9)',
              BulletinCategory.groupNamed =>
                'Named group (${bulletin.groupName ?? '—'})',
            },
          ),
        ],
      ),
    );
  }

  String _formatAbsolute(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _TransportBadge extends StatelessWidget {
  const _TransportBadge({required this.transport});
  final BulletinTransport transport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = transport == BulletinTransport.rf ? 'RF' : 'IS';
    final color = transport == BulletinTransport.rf
        ? theme.colorScheme.tertiaryContainer
        : theme.colorScheme.secondaryContainer;
    final onColor = transport == BulletinTransport.rf
        ? theme.colorScheme.onTertiaryContainer
        : theme.colorScheme.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: onColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
