import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../core/packet/station.dart';
import '../../core/packet/symbol_resolver.dart';
import '../../screens/message_thread_screen.dart';
import '../../services/station_service.dart';
import '../utils/distance_formatter.dart';
import '../utils/maidenhead.dart';
import '../utils/platform_route.dart';
import '../utils/wx_data.dart';
import 'aprs_symbol_widget.dart';

String _distanceText(LatLng from, Station to, {required bool imperial}) {
  final km = const Distance().as(
    LengthUnit.Kilometer,
    from,
    LatLng(to.lat, to.lon),
  );
  return formatDistance(km, imperial: imperial);
}

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
  const StationInfoSheet({
    super.key,
    required this.station,
    this.referencePosition,
    this.onShowOnMap,
  });

  final Station station;

  /// When provided, the sheet shows the distance from this position to the
  /// station. Typically the current map center or GPS location.
  final LatLng? referencePosition;

  /// When provided, a "Show on map" button is displayed. The callback should
  /// close the sheet (via [Navigator.pop]) and navigate to the map.
  final VoidCallback? onShowOnMap;

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
    final grid = maidenheadLocator(station.lat, station.lon);

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

            // Grid square
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.grid_on,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  'Grid $grid',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),

            // Weather data or raw comment
            if (station.type == StationType.weather) ...[
              const SizedBox(height: 12),
              _WxSection(
                comment: station.comment,
                colorScheme: colorScheme,
                textTheme: textTheme,
              ),
            ] else if (hasComment) ...[
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

            // Distance from reference point (map center or GPS)
            if (referencePosition != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.straighten,
                    size: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _distanceText(
                      referencePosition!,
                      station,
                      imperial: context
                          .watch<StationService>()
                          .useImperialUnits,
                    ),
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 16),

            // Show on map button (only when launched from outside the map).
            if (onShowOnMap != null) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Symbols.map),
                  label: const Text('Show on map'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    onShowOnMap!();
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],

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

// ---------------------------------------------------------------------------
// Weather helpers
// ---------------------------------------------------------------------------

class _WxSection extends StatelessWidget {
  const _WxSection({
    required this.comment,
    required this.colorScheme,
    required this.textTheme,
  });

  final String comment;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final wx = WxData.parse(comment);
    if (wx == null) {
      // Not a parseable WX string — fall back to raw text.
      return Text(
        comment,
        style: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      );
    }

    final rows = <_WxRow>[];

    if (wx.tempF != null) {
      final c = wx.tempC!;
      rows.add(
        _WxRow(
          icon: Icons.thermostat,
          label: '${wx.tempF!.round()}°F  /  ${c.round()}°C',
        ),
      );
    }

    if (wx.humidity != null) {
      rows.add(
        _WxRow(icon: Icons.water_drop, label: '${wx.humidity}% humidity'),
      );
    }

    if (wx.pressureHpa != null) {
      rows.add(
        _WxRow(
          icon: Icons.speed,
          label: '${wx.pressureHpa!.toStringAsFixed(1)} hPa',
        ),
      );
    }

    final wind = wx.windSummary;
    if (wind != null) {
      rows.add(_WxRow(icon: Icons.air, label: wind));
    }

    if (wx.rainfall1h != null) {
      final inches = wx.rainfall1h! / 100.0;
      rows.add(
        _WxRow(icon: Icons.grain, label: '${inches.toStringAsFixed(2)}" / hr'),
      );
    }

    if (wx.luminosity != null) {
      rows.add(
        _WxRow(icon: Icons.wb_sunny_outlined, label: '${wx.luminosity} W/m²'),
      );
    }

    if (rows.isEmpty) {
      return Text(
        comment,
        style: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows
          .map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(r.icon, size: 16, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                    r.label,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _WxRow {
  const _WxRow({required this.icon, required this.label});
  final IconData icon;
  final String label;
}
