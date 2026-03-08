import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../services/station_service.dart';
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
    required this.mapController,
    required this.markers,
    required this.tileUrl,
    required this.onNavigateToSettings,
  });

  final StationService service;
  final MapController mapController;
  final List<Marker> markers;
  final String tileUrl;
  final VoidCallback onNavigateToSettings;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    if (width < 600) {
      return MobileScaffold(
        service: service,
        mapController: mapController,
        markers: markers,
        tileUrl: tileUrl,
        onNavigateToSettings: onNavigateToSettings,
      );
    }
    if (width < 1024) {
      return TabletScaffold(
        service: service,
        mapController: mapController,
        markers: markers,
        tileUrl: tileUrl,
        onNavigateToSettings: onNavigateToSettings,
      );
    }
    return DesktopScaffold(
      service: service,
      mapController: mapController,
      markers: markers,
      tileUrl: tileUrl,
      onNavigateToSettings: onNavigateToSettings,
    );
  }
}
