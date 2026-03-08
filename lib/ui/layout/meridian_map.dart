import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// The core map widget used by all scaffold layouts.
///
/// Encapsulates flutter_map configuration, tile layer setup, and the marker
/// layer. All map logic lives here so the three scaffold variants share a
/// single, consistent map implementation.
class MeridianMap extends StatelessWidget {
  const MeridianMap({
    super.key,
    required this.mapController,
    required this.markers,
    required this.tileUrl,
    this.initialCenter = const LatLng(39.0, -77.0),
    this.initialZoom = 9.0,
  });

  final MapController mapController;
  final List<Marker> markers;

  /// OSM-compatible tile URL with `{z}`, `{x}`, `{y}` placeholders.
  /// For tiles that use subdomain rotation include `{s}` and set
  /// the appropriate subdomains on [TileLayer].
  final String tileUrl;

  final LatLng initialCenter;
  final double initialZoom;

  /// Whether the tile URL requires subdomain rotation (CartoDB dark tiles).
  bool get _usesSubdomains => tileUrl.contains('{s}');

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: initialCenter,
        initialZoom: initialZoom,
      ),
      children: [
        TileLayer(
          urlTemplate: tileUrl,
          userAgentPackageName: 'com.meridianaprs.app',
          subdomains: _usesSubdomains ? const ['a', 'b', 'c', 'd'] : const [],
        ),
        MarkerLayer(markers: markers),
      ],
    );
  }
}
