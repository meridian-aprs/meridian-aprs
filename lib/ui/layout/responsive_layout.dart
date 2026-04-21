import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/packet/station.dart';
import '../../map/meridian_tile_provider.dart';

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
    required this.meridianTileProvider,
    required this.onNavigateToSettings,
    this.initialCenter = const LatLng(39.0, -77.0),
    this.initialZoom = 9.0,
    this.northUpLocked = true,
    required this.onToggleNorthUp,
    this.showTracks = false,
    this.trackPolylines = const [],
    required this.onOpenFilterPanel,
    this.activeFilterLabel,
    this.visibleStationCount = 0,
    this.totalStationCount = 0,
    this.nearestWxStation,
    this.isFilterActive = false,
    this.onMapLongPress,
  });

  final StationService service;
  final MapController mapController;
  final List<Marker> markers;
  final String tileUrl;
  final MeridianTileProvider meridianTileProvider;
  final VoidCallback onNavigateToSettings;
  final LatLng initialCenter;
  final double initialZoom;
  final bool northUpLocked;
  final VoidCallback onToggleNorthUp;
  final bool showTracks;
  final List<Polyline> trackPolylines;
  final VoidCallback onOpenFilterPanel;

  /// Non-null label shown as a chip on the map surface when a non-default
  /// time filter is active.
  final String? activeFilterLabel;

  final int visibleStationCount;
  final int totalStationCount;

  /// Nearest weather station within 50 km of the map center.
  /// Non-null only when the overlay is enabled and a WX station is in range.
  final Station? nearestWxStation;

  /// Whether any map filter is set to a non-default value. Used to badge the
  /// filter FAB/button so users know active filters are in effect.
  final bool isFilterActive;

  /// Called when the user long-presses on the map canvas.
  final void Function(LatLng)? onMapLongPress;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    if (width < 600) {
      return MobileScaffold(
        service: service,
        mapController: mapController,
        markers: markers,
        tileUrl: tileUrl,
        meridianTileProvider: meridianTileProvider,
        onNavigateToSettings: onNavigateToSettings,
        initialCenter: initialCenter,
        initialZoom: initialZoom,
        northUpLocked: northUpLocked,
        onToggleNorthUp: onToggleNorthUp,
        showTracks: showTracks,
        trackPolylines: trackPolylines,
        onOpenFilterPanel: onOpenFilterPanel,
        activeFilterLabel: activeFilterLabel,
        visibleStationCount: visibleStationCount,
        totalStationCount: totalStationCount,
        nearestWxStation: nearestWxStation,
        isFilterActive: isFilterActive,
        onMapLongPress: onMapLongPress,
      );
    }
    if (width < 1024) {
      return TabletScaffold(
        service: service,
        mapController: mapController,
        markers: markers,
        tileUrl: tileUrl,
        meridianTileProvider: meridianTileProvider,
        onNavigateToSettings: onNavigateToSettings,
        initialCenter: initialCenter,
        initialZoom: initialZoom,
        northUpLocked: northUpLocked,
        onToggleNorthUp: onToggleNorthUp,
        showTracks: showTracks,
        trackPolylines: trackPolylines,
        onOpenFilterPanel: onOpenFilterPanel,
        activeFilterLabel: activeFilterLabel,
        visibleStationCount: visibleStationCount,
        totalStationCount: totalStationCount,
        nearestWxStation: nearestWxStation,
        isFilterActive: isFilterActive,
        onMapLongPress: onMapLongPress,
      );
    }
    return DesktopScaffold(
      service: service,
      mapController: mapController,
      markers: markers,
      tileUrl: tileUrl,
      meridianTileProvider: meridianTileProvider,
      onNavigateToSettings: onNavigateToSettings,
      initialCenter: initialCenter,
      initialZoom: initialZoom,
      northUpLocked: northUpLocked,
      onToggleNorthUp: onToggleNorthUp,
      showTracks: showTracks,
      trackPolylines: trackPolylines,
      onOpenFilterPanel: onOpenFilterPanel,
      activeFilterLabel: activeFilterLabel,
      visibleStationCount: visibleStationCount,
      totalStationCount: totalStationCount,
      nearestWxStation: nearestWxStation,
      isFilterActive: isFilterActive,
      onMapLongPress: onMapLongPress,
    );
  }
}
