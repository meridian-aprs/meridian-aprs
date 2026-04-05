import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/packet/station.dart';
import '../../core/packet/symbol_resolver.dart';
import '../../screens/message_thread_screen.dart';
import '../utils/platform_route.dart';
import 'aprs_symbol_widget.dart';

String _formatLastHeard(DateTime lastHeard) {
  final diff = DateTime.now().difference(lastHeard);
  if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

/// A Material 3 bottom sheet displaying APRS station details.
///
/// Intended for use with [showModalBottomSheet]:
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   builder: (_) => StationInfoSheet(station: station),
/// );
/// ```
class StationInfoSheet extends StatelessWidget {
  const StationInfoSheet({super.key, required this.station});

  final Station station;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    final symbolName = SymbolResolver.symbolName(
      station.symbolTable,
      station.symbolCode,
    );
    final relativeTime = _formatLastHeard(station.lastHeard);
    final hasComment = station.comment.isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 32,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Callsign
            Text(
              station.callsign,
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),

            const SizedBox(height: 8),

            // Symbol type row
            Row(
              children: [
                AprsSymbolWidget(
                  symbolTable: station.symbolTable,
                  symbolCode: station.symbolCode,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  symbolName,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),

            // Comment (conditional)
            if (hasComment) ...[
              const SizedBox(height: 12),
              Text(
                station.comment,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],

            // Device (conditional)
            if (station.device != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.memory,
                    size: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    station.device!,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 12),

            // Last heard
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  'Last heard: $relativeTime',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Message button
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                icon: const Icon(Symbols.message),
                label: Text('Message ${station.callsign}'),
                onPressed: () {
                  final nav = Navigator.of(context);
                  nav.pop();
                  nav.push(
                    buildPlatformRoute<void>(
                      (_) =>
                          MessageThreadScreen(peerCallsign: station.callsign),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
