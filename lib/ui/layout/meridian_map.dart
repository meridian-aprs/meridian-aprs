import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../core/packet/station.dart';
import '../../core/transport/aprs_transport.dart' show ConnectionStatus;
import '../../services/station_service.dart';
import '../utils/wx_data.dart';
import '../widgets/station_info_sheet.dart';

/// The core map widget used by all scaffold layouts.
///
/// Encapsulates flutter_map configuration, tile layer setup, and the marker
/// layer. All map logic lives here so the three scaffold variants share a
/// single, consistent map implementation.
///
/// When [connectionStatus] is [ConnectionStatus.connecting], a small
/// [_ConnectingBanner] is overlaid at the top of the map canvas to indicate
/// that the APRS-IS connection is being established. The banner does not block
/// map interaction.
///
/// When [isAnyConnected] is false and [onNotConnectedTap] is provided, a
/// subtle nudge chip is shown at the top of the map prompting the user to
/// open the Connection screen. It fades out as soon as any transport connects.

String _formatAge(DateTime lastHeard) {
  final diff = DateTime.now().difference(lastHeard);
  if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

class MeridianMap extends StatelessWidget {
  const MeridianMap({
    super.key,
    required this.mapController,
    required this.markers,
    required this.tileUrl,
    this.tileProvider,
    this.connectionStatus = ConnectionStatus.disconnected,
    this.initialCenter = const LatLng(39.0, -77.0),
    this.initialZoom = 9.0,
    this.northUpLocked = true,
    this.isAnyConnected = true,
    this.onNotConnectedTap,
    this.showTracks = false,
    this.trackPolylines = const [],
    this.activeFilterLabel,
    this.onActiveFilterTap,
    this.visibleStationCount = 0,
    this.totalStationCount = 0,
    this.showCountChip = false,
    this.nearestWxStation,
    this.onMapLongPress,
  });

  final MapController mapController;
  final List<Marker> markers;

  /// Stadia Maps tile URL with `{z}`, `{x}`, `{y}` placeholders.
  final String tileUrl;

  /// Optional tile provider — use a [CachedTileProvider] to avoid redundant
  /// network requests. Falls back to flutter_map's default when null.
  final TileProvider? tileProvider;

  final ConnectionStatus connectionStatus;
  final LatLng initialCenter;
  final double initialZoom;

  /// When true, map rotation gestures are disabled and the map stays
  /// oriented north-up. When false, the user can freely rotate the map.
  final bool northUpLocked;

  /// Whether any transport (APRS-IS or TNC) is currently connected.
  /// When false, the not-connected nudge chip is shown over the map.
  final bool isAnyConnected;

  /// Called when the user taps the not-connected nudge chip.
  final VoidCallback? onNotConnectedTap;

  /// Whether to render station movement tracks.
  final bool showTracks;

  /// Pre-built polylines from each station's position history.
  /// Only rendered when [showTracks] is true.
  final List<Polyline> trackPolylines;

  /// When non-null, a compact chip is shown on the map surface indicating the
  /// active time filter (e.g. "30 min"). Tapping it calls [onActiveFilterTap].
  final String? activeFilterLabel;

  /// Called when the user taps the active filter chip.
  final VoidCallback? onActiveFilterTap;

  /// Number of stations passing the current display filter.
  final int visibleStationCount;

  /// Total number of known stations (unfiltered).
  final int totalStationCount;

  /// When false, suppresses the station count chip (use when the caller renders
  /// it itself, e.g. MobileScaffold aligns it with the beacon FAB).
  final bool showCountChip;

  /// Nearest weather station within 50 km of the map center.
  /// When non-null, a compact weather conditions chip is shown over the map.
  final Station? nearestWxStation;

  /// Called when the user long-presses on the map canvas. Receives the
  /// geographic coordinate of the long-press point. Use this to drop a pin.
  final void Function(LatLng)? onMapLongPress;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter: initialCenter,
            initialZoom: initialZoom,
            interactionOptions: InteractionOptions(
              flags: northUpLocked
                  ? InteractiveFlag.all & ~InteractiveFlag.rotate
                  : InteractiveFlag.all,
            ),
            onLongPress: onMapLongPress != null
                ? (_, latLng) => onMapLongPress!(latLng)
                : null,
          ),
          children: [
            TileLayer(
              urlTemplate: tileUrl,
              tileProvider: tileProvider,
              userAgentPackageName: 'com.meridianaprs.app',
            ),
            PolylineLayer(
              polylines: showTracks ? trackPolylines : const <Polyline>[],
            ),
            MarkerLayer(markers: markers),
            const _ScaleBarLayer(),
            RichAttributionWidget(
              attributions: [
                TextSourceAttribution('Stadia Maps'),
                TextSourceAttribution('OpenMapTiles'),
                TextSourceAttribution('OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
        if (connectionStatus == ConnectionStatus.connecting)
          const Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(child: _ConnectingBanner()),
          ),
        if (onNotConnectedTap != null)
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(
              child: _NotConnectedNudge(
                visible: !isAnyConnected,
                onTap: onNotConnectedTap!,
              ),
            ),
          ),
        if (activeFilterLabel != null)
          Positioned(
            top: 12,
            left: 12,
            child: _ActiveFilterChip(
              label: activeFilterLabel!,
              onTap: onActiveFilterTap,
            ),
          ),
        if (showCountChip &&
            visibleStationCount < totalStationCount &&
            totalStationCount > 0)
          Positioned(
            bottom: 32,
            left: 12,
            child: _StationCountChip(
              visible: visibleStationCount,
              total: totalStationCount,
            ),
          ),
        if (nearestWxStation != null)
          Positioned(
            top: 12,
            right: 12,
            child: _WeatherOverlayChip(station: nearestWxStation!),
          ),
      ],
    );
  }
}

/// Subtle nudge chip shown on the map when no transport is connected.
///
/// Fades in/out with [AnimatedOpacity] so the transition is gentle. Uses
/// [IgnorePointer] while invisible to avoid intercepting map taps.
class _NotConnectedNudge extends StatelessWidget {
  const _NotConnectedNudge({required this.visible, required this.onTap});

  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 400),
      child: IgnorePointer(
        ignoring: !visible,
        child: ActionChip(
          avatar: const Icon(Symbols.signal_disconnected, size: 16),
          label: const Text('Not connected — tap to connect'),
          onPressed: onTap,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

/// Compact chip shown on the map surface when a non-default time filter is
/// active. Tapping it opens the filter panel.
class _ActiveFilterChip extends StatelessWidget {
  const _ActiveFilterChip({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Symbols.filter_list, size: 16),
      label: Text(label),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Compact chip shown bottom-left when fewer stations are visible than known.
/// Communicates the active filter impact: "14 of 47 stations".
class _StationCountChip extends StatelessWidget {
  const _StationCountChip({required this.visible, required this.total});

  final int visible;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: const Icon(Icons.layers, size: 16),
      label: Text('$visible of $total stations'),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Compact weather conditions chip shown on the map when a nearby WX station
/// is detected and the overlay is enabled.
class _WeatherOverlayChip extends StatelessWidget {
  const _WeatherOverlayChip({required this.station});

  final Station station;

  @override
  Widget build(BuildContext context) {
    final wx = WxData.parse(station.comment);
    if (wx == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final useCelsius = context.watch<StationService>().weatherOverlayUseCelsius;

    final tempStr = wx.tempF != null
        ? useCelsius
              ? '${wx.tempC!.round()}°C'
              : '${wx.tempF!.round()}°F'
        : null;
    final humStr = wx.humidity != null ? '${wx.humidity}%' : null;
    final windStr = wx.windSummary;

    final parts = [?tempStr, ?humStr, ?windStr];

    if (parts.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        builder: (_) => StationInfoSheet(station: station),
      ),
      child: Card(
        elevation: 2,
        color: theme.colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.wb_cloudy_outlined,
                size: 14,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 6),
              IntrinsicWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      parts.join('  ·  '),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          station.callsign,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer
                                .withAlpha(180),
                          ),
                        ),
                        Text(
                          _formatAge(station.lastHeard),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer
                                .withAlpha(180),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A flutter_map child layer that draws a distance scale bar in the
/// bottom-left corner of the map. The bar width is snapped to a round-number
/// distance so the label is always human-friendly (e.g. "1 km", "500 m").
///
/// Built as a flutter_map layer (a child of [FlutterMap.children]) so it can
/// read [MapCamera.of] to stay in sync with the current zoom level without
/// converting [MeridianMap] to a StatefulWidget.
class _ScaleBarLayer extends StatelessWidget {
  const _ScaleBarLayer();

  // Metric candidate distances in metres. Snaps to the closest to [_targetPx].
  static const _metricCandidates = <({int metres, String label})>[
    (metres: 50, label: '50 m'),
    (metres: 100, label: '100 m'),
    (metres: 200, label: '200 m'),
    (metres: 500, label: '500 m'),
    (metres: 1000, label: '1 km'),
    (metres: 2000, label: '2 km'),
    (metres: 5000, label: '5 km'),
    (metres: 10000, label: '10 km'),
    (metres: 20000, label: '20 km'),
    (metres: 50000, label: '50 km'),
    (metres: 100000, label: '100 km'),
    (metres: 200000, label: '200 km'),
    (metres: 500000, label: '500 km'),
  ];

  // Imperial candidates: metres value chosen to produce a round ft/mi label.
  static const _imperialCandidates = <({int metres, String label})>[
    (metres: 30, label: '100 ft'),
    (metres: 91, label: '300 ft'),
    (metres: 152, label: '500 ft'),
    (metres: 305, label: '1000 ft'),
    (metres: 805, label: '½ mi'),
    (metres: 1609, label: '1 mi'),
    (metres: 3219, label: '2 mi'),
    (metres: 8047, label: '5 mi'),
    (metres: 16093, label: '10 mi'),
    (metres: 40234, label: '25 mi'),
    (metres: 80467, label: '50 mi'),
    (metres: 160934, label: '100 mi'),
    (metres: 402336, label: '250 mi'),
    (metres: 804672, label: '500 mi'),
  ];

  static const double _targetPx = 80;

  /// Metres per screen pixel at the given latitude and zoom level.
  static double _metersPerPixel(double latDeg, double zoom) {
    const earthCircumference = 2 * math.pi * 6378137.0;
    return earthCircumference *
        math.cos(latDeg * math.pi / 180) /
        (256 * math.pow(2, zoom));
  }

  @override
  Widget build(BuildContext context) {
    final imperial = context.watch<StationService>().useImperialUnits;
    final candidates = imperial ? _imperialCandidates : _metricCandidates;

    final camera = MapCamera.of(context);
    final mpp = _metersPerPixel(camera.center.latitude, camera.zoom);
    final targetM = mpp * _targetPx;

    // Pick the candidate whose metre value is closest to targetM.
    var best = candidates.first;
    double bestDiff = double.infinity;
    for (final c in candidates) {
      final diff = (c.metres - targetM).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = c;
      }
    }

    final barPx = best.metres / mpp;
    final label = best.label;

    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurface;

    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 12, bottom: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                shadows: [
                  Shadow(
                    color: theme.colorScheme.surface.withAlpha(180),
                    blurRadius: 3,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            CustomPaint(
              size: Size(barPx, 6),
              painter: _ScaleBarPainter(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScaleBarPainter extends CustomPainter {
  const _ScaleBarPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    // Horizontal bar
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      paint,
    );
    // Left tick
    canvas.drawLine(Offset(0, 0), Offset(0, size.height), paint);
    // Right tick
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ScaleBarPainter old) => old.color != color;
}

class _ConnectingBanner extends StatelessWidget {
  const _ConnectingBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator.adaptive(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              'Connecting to APRS-IS\u2026',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
