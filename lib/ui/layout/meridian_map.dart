import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/transport/aprs_transport.dart' show ConnectionStatus;

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
