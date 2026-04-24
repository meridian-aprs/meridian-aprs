/// Bulletins tab body inside [MessagesScreen].
///
/// Shows the chronological bulletin feed with filter chips (All / General /
/// Groups / My bulletins). Gates on `BulletinService.showBulletins` and
/// displays the location-unknown banner when APRS-IS is connected but the
/// operator hasn't set a station location (spec §4.4). "My bulletins" is
/// empty in PR 3 — `OutgoingBulletin` CRUD lands in PR 4.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../core/connection/connection_registry.dart';
import '../models/bulletin.dart';
import '../services/bulletin_service.dart';
import '../services/station_settings_service.dart';
import '../ui/utils/platform_route.dart';
import 'bulletin_detail_screen.dart';

enum _BulletinFilter { all, general, groups, mine }

class BulletinsTab extends StatefulWidget {
  const BulletinsTab({super.key});

  @override
  State<BulletinsTab> createState() => _BulletinsTabState();
}

class _BulletinsTabState extends State<BulletinsTab> {
  _BulletinFilter _filter = _BulletinFilter.all;

  @override
  Widget build(BuildContext context) {
    final bulletins = context.watch<BulletinService>();
    final station = context.watch<StationSettingsService>();
    final registry = context.watch<ConnectionRegistry>();

    if (!bulletins.showBulletins) {
      return const _BulletinsDisabledState();
    }

    final aprsIsConn = registry.byId('aprs_is');
    final aprsIsConnected = aprsIsConn?.isConnected ?? false;
    final hasLocation = station.hasManualPosition;
    final showLocationBanner = aprsIsConnected && !hasLocation;

    final visible = _applyFilter(
      bulletins.bulletins,
      _filter,
      showLocationBanner,
    );

    return Column(
      children: [
        if (showLocationBanner)
          _LocationUnknownBanner(
            onSetLocation: () {
              // v0.12 onboarding handles initial location entry. Keep this
              // hook here; the routing target is introduced in PR 5 when the
              // Settings → My Station "Set location" action is added.
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Open Settings → My Station to set your location. '
                    'Direct hook lands in PR 5.',
                  ),
                ),
              );
            },
          ),
        _FilterChipRow(
          current: _filter,
          onChanged: (f) => setState(() => _filter = f),
        ),
        Expanded(
          child: visible.isEmpty
              ? _EmptyForFilter(filter: _filter)
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 2),
                  itemBuilder: (ctx, i) {
                    final b = visible[i];
                    return _BulletinRow(
                      bulletin: b,
                      onTap: () {
                        if (!b.isRead) bulletins.markRead(b.id);
                        Navigator.push(
                          ctx,
                          buildPlatformRoute(
                            (_) => BulletinDetailScreen(bulletinId: b.id),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Apply both the filter-chip choice and the location-aware scope gate.
  /// When [hideApisGeneralWithoutLocation] is true, general bulletins that
  /// were heard only over APRS-IS are dropped — matching the banner copy.
  List<Bulletin> _applyFilter(
    List<Bulletin> all,
    _BulletinFilter filter,
    bool hideApisGeneralWithoutLocation,
  ) {
    Iterable<Bulletin> base = all;
    if (hideApisGeneralWithoutLocation) {
      base = base.where((b) {
        if (b.category != BulletinCategory.general) return true;
        final onlyIs =
            b.transports.length == 1 &&
            b.transports.contains(BulletinTransport.aprsIs);
        return !onlyIs;
      });
    }
    final filtered = switch (filter) {
      _BulletinFilter.all => base,
      _BulletinFilter.general => base.where(
        (b) => b.category == BulletinCategory.general,
      ),
      _BulletinFilter.groups => base.where(
        (b) => b.category == BulletinCategory.groupNamed,
      ),
      // "My bulletins" is empty in PR 3 — OutgoingBulletin arrives in PR 4.
      _BulletinFilter.mine => const Iterable<Bulletin>.empty(),
    };
    return filtered.toList();
  }
}

// ---------------------------------------------------------------------------
// Filter chip row
// ---------------------------------------------------------------------------

class _FilterChipRow extends StatelessWidget {
  const _FilterChipRow({required this.current, required this.onChanged});
  final _BulletinFilter current;
  final ValueChanged<_BulletinFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Wrap(
        spacing: 8,
        children: [
          for (final f in _BulletinFilter.values)
            ChoiceChip(
              label: Text(_labelFor(f)),
              selected: current == f,
              onSelected: (_) => onChanged(f),
            ),
        ],
      ),
    );
  }

  String _labelFor(_BulletinFilter f) => switch (f) {
    _BulletinFilter.all => 'All',
    _BulletinFilter.general => 'General',
    _BulletinFilter.groups => 'Groups',
    _BulletinFilter.mine => 'My bulletins',
  };
}

// ---------------------------------------------------------------------------
// Row
// ---------------------------------------------------------------------------

class _BulletinRow extends StatelessWidget {
  const _BulletinRow({required this.bulletin, required this.onTap});

  final Bulletin bulletin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUnread = !bulletin.isRead;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Symbols.campaign,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    bulletin.addressee,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '· ${bulletin.sourceCallsign}',
                    style: theme.textTheme.labelSmall,
                  ),
                  const Spacer(),
                  for (final t in bulletin.transports)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: _TransportChip(transport: t),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    _formatTime(bulletin.lastHeardAt),
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                bulletin.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: isUnread ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}

class _TransportChip extends StatelessWidget {
  const _TransportChip({required this.transport});
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: onColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Location unknown banner
// ---------------------------------------------------------------------------

class _LocationUnknownBanner extends StatelessWidget {
  const _LocationUnknownBanner({required this.onSetLocation});
  final VoidCallback onSetLocation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              Symbols.location_off,
              color: theme.colorScheme.onTertiaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'General APRS-IS bulletins are hidden because your station '
                'location is not set. RF bulletins and subscribed named '
                'groups are unaffected.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ),
            ),
            TextButton(
              onPressed: onSetLocation,
              child: const Text('Set location'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty states
// ---------------------------------------------------------------------------

class _BulletinsDisabledState extends StatelessWidget {
  const _BulletinsDisabledState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.notifications_off,
              size: 64,
              color: theme.colorScheme.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text('Bulletins are hidden', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Turn on "Show bulletins" in Settings → Messaging → Bulletins '
              'to see the feed.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyForFilter extends StatelessWidget {
  const _EmptyForFilter({required this.filter});
  final _BulletinFilter filter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String title;
    final String body;
    switch (filter) {
      case _BulletinFilter.all:
        title = 'No bulletins yet';
        body =
            'Bulletins broadcast on APRS (BLN0–BLN9 and named groups) will '
            'appear here when they arrive.';
      case _BulletinFilter.general:
        title = 'No general bulletins';
        body = 'No BLN0–BLN9 bulletins are in scope right now.';
      case _BulletinFilter.groups:
        title = 'No group bulletins';
        body =
            'Subscribe to named bulletin groups like WX or SRARC in '
            'Settings → Messaging → Bulletins.';
      case _BulletinFilter.mine:
        title = 'No bulletins from you';
        body =
            'Bulletins you transmit will appear here. Bulletin composition '
            'ships in the next release.';
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.campaign,
              size: 56,
              color: theme.colorScheme.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              body,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
