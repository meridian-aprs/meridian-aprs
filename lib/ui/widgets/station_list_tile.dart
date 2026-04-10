import 'package:flutter/material.dart';

import '../../core/packet/station.dart';
import 'aprs_symbol_widget.dart';

/// Formats a [DateTime] as a human-readable relative timestamp.
String _relativeTime(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

/// A list tile representing a single APRS [Station].
///
/// Shows the station's APRS symbol, callsign, last-heard relative timestamp,
/// and an optional comment truncated to one line.
///
/// Meets the 44 px minimum tap target requirement via [ListTile]'s default
/// minimum height.
class StationListTile extends StatelessWidget {
  const StationListTile({
    super.key,
    required this.station,
    required this.onTap,
  });

  final Station station;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListTile(
      minTileHeight: 44,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: AprsSymbolWidget(
        symbolTable: station.symbolTable,
        symbolCode: station.symbolCode,
        size: 32,
      ),
      title: Text(
        station.callsign,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: colorScheme.onSurface,
        ),
      ),
      subtitle: station.comment.isNotEmpty
          ? Text(
              station.comment,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      trailing: Text(
        _relativeTime(station.lastHeard),
        style: theme.textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: onTap,
    );
  }
}
