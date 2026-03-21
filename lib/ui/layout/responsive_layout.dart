import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/transport/aprs_transport.dart';
import '../../services/station_service.dart';
import '../../services/tnc_service.dart';
import 'desktop_scaffold.dart';
import 'mobile_scaffold.dart';
import 'tablet_scaffold.dart';

/// Selects the appropriate scaffold layout based on the current window width.
///
/// Breakpoints:
/// - < 600 px  → [MobileScaffold] (full-screen map, FABs, bottom sheets)
/// - 600–1024 px → [TabletScaffold] (collapsed navigation rail + bottom panel)
/// - > 1024 px → [DesktopScaffold] (expanded navigation rail + side panel)
class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({
    super.key,
    required this.service,
    required this.tncService,
    required this.mapController,
    required this.markers,
    required this.tileUrl,
    required this.onNavigateToSettings,
    this.connectionStatus = ConnectionStatus.disconnected,
    this.tncConnectionStatus = ConnectionStatus.disconnected,
    this.initialCenter = const LatLng(39.0, -77.0),
    this.initialZoom = 9.0,
  });

  final StationService service;
  final TncService tncService;
  final MapController mapController;
  final List<Marker> markers;
  final String tileUrl;
  final VoidCallback onNavigateToSettings;
  final ConnectionStatus connectionStatus;
  final ConnectionStatus tncConnectionStatus;
  final LatLng initialCenter;
  final double initialZoom;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    if (width < 600) {
      return MobileScaffold(
        service: service,
        tncService: tncService,
        mapController: mapController,
        markers: markers,
        tileUrl: tileUrl,
        onNavigateToSettings: onNavigateToSettings,
        connectionStatus: connectionStatus,
        tncConnectionStatus: tncConnectionStatus,
        initialCenter: initialCenter,
        initialZoom: initialZoom,
      );
    }
    if (width < 1024) {
      return TabletScaffold(
        service: service,
        tncService: tncService,
        mapController: mapController,
        markers: markers,
        tileUrl: tileUrl,
        onNavigateToSettings: onNavigateToSettings,
        connectionStatus: connectionStatus,
        tncConnectionStatus: tncConnectionStatus,
        initialCenter: initialCenter,
        initialZoom: initialZoom,
      );
    }
    return DesktopScaffold(
      service: service,
      tncService: tncService,
      mapController: mapController,
      markers: markers,
      tileUrl: tileUrl,
      onNavigateToSettings: onNavigateToSettings,
      connectionStatus: connectionStatus,
      tncConnectionStatus: tncConnectionStatus,
      initialCenter: initialCenter,
      initialZoom: initialZoom,
    );
  }
}
