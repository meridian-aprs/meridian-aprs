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
    this.connectionStatus = ConnectionStatus.disconnected,
    this.initialCenter = const LatLng(39.0, -77.0),
    this.initialZoom = 9.0,
    this.northUpLocked = true,
    this.isAnyConnected = true,
    this.onNotConnectedTap,
  });

  final MapController mapController;
  final List<Marker> markers;

  /// OSM-compatible tile URL with `{z}`, `{x}`, `{y}` placeholders.
  /// For tiles that use subdomain rotation include `{s}` and set
  /// the appropriate subdomains on [TileLayer].
  final String tileUrl;

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

  /// Whether the tile URL requires subdomain rotation (CartoDB dark tiles).
  bool get _usesSubdomains => tileUrl.contains('{s}');

  /// Whether these are dark tiles that need a brightness boost to remain
  /// readable (CartoDB dark_all is near-black by default).
  bool get _isDarkTile => tileUrl.contains('dark');

  // Lifts CartoDB dark tiles from near-black to a readable dark-gray.
  // Adds ~26/255 (~10%) to every RGB channel without touching alpha.
  static const _darkTileBrightnessFilter = ColorFilter.matrix([
    1,
    0,
    0,
    0,
    26,
    0,
    1,
    0,
    0,
    26,
    0,
    0,
    1,
    0,
    26,
    0,
    0,
    0,
    1,
    0,
  ]);

  @override
  Widget build(BuildContext context) {
    Widget tileLayer = TileLayer(
      urlTemplate: tileUrl,
      userAgentPackageName: 'com.meridianaprs.app',
      subdomains: _usesSubdomains ? const ['a', 'b', 'c', 'd'] : const [],
    );

    if (_isDarkTile) {
      tileLayer = ColorFiltered(
        colorFilter: _darkTileBrightnessFilter,
        child: tileLayer,
      );
    }

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
            tileLayer,
            MarkerLayer(markers: markers),
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
              child: CircularProgressIndicator(
                strokeWidth: 2,
                strokeCap: StrokeCap.round,
              ),
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
