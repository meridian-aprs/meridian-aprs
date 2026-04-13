import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../map/meridian_tile_provider.dart';

import '../../core/connection/connection_registry.dart';
import '../../core/packet/station.dart';
import '../../screens/connection_screen.dart';
import '../../screens/messages_screen.dart';
import '../../screens/packet_log_screen.dart';
import '../../screens/station_list_screen.dart';
import '../../services/beaconing_service.dart';
import '../../services/message_service.dart';
import '../../services/station_service.dart';
import '../../services/station_settings_service.dart';
import '../widgets/beacon_fab.dart';
import '../widgets/connection_nav_icon.dart';
import '../widgets/meridian_status_pill.dart';
import '../widgets/station_info_sheet.dart';
import 'meridian_map.dart';

/// Mobile (< 600 px) scaffold: full-screen map, FAB cluster, M3 Navigation Bar.
///
/// The [NavigationBar] at the bottom provides access to all primary
/// destinations. Content switches in-place via an [IndexedStack] so the
/// navigation bar remains visible on every tab.
class MobileScaffold extends StatefulWidget {
  const MobileScaffold({
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
  final String? activeFilterLabel;
  final int visibleStationCount;
  final int totalStationCount;
  final Station? nearestWxStation;
  final bool isFilterActive;
  final void Function(LatLng)? onMapLongPress;

  @override
  State<MobileScaffold> createState() => _MobileScaffoldState();
}

class _MobileScaffoldState extends State<MobileScaffold> {
  int _selectedIndex = 0;
  bool _locating = false;

  void _navigateToConnection() {
    setState(() => _selectedIndex = 4);
  }

  void _onDestinationSelected(int index) {
    HapticFeedback.selectionClick();
    setState(() => _selectedIndex = index);
  }

  Future<void> _centerOnLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      // Try to check if location services work at all — desktop platforms
      // throw UnimplementedError if geolocator has no implementation.
      bool serviceEnabled;
      try {
        serviceEnabled = await Geolocator.isLocationServiceEnabled();
      } on UnimplementedError {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location is not available on this platform.'),
          ),
        );
        return;
      }
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location services are disabled.')),
        );
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission denied.')),
        );
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      widget.mapController.move(
        LatLng(position.latitude, position.longitude),
        13.0,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not get location: $e')));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _showStationOnMap(Station station) {
    setState(() => _selectedIndex = 0);
    widget.mapController.move(LatLng(station.lat, station.lon), 13.0);
  }

  void _showOwnStation() {
    final settings = context.read<StationSettingsService>();
    final service = context.read<StationService>();

    if (settings.callsign.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set your callsign in Settings first.')),
      );
      return;
    }

    final ownAddress = settings.fullAddress;
    final station = service.currentStations[ownAddress];

    if (station == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$ownAddress hasn\'t been heard yet.')),
      );
      return;
    }

    setState(() => _selectedIndex = 0);
    widget.mapController.move(LatLng(station.lat, station.lon), 13.0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: context,
        builder: (_) => StationInfoSheet(station: station),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final registry = context.watch<ConnectionRegistry>();
    return Scaffold(
      appBar: _selectedIndex == 0
          ? AppBar(
              title: const Text('Meridian'),
              actions: [
                ...registry.available.map(
                  (conn) => MeridianStatusPill(
                    status: conn.status,
                    label: conn.displayName,
                    onTap: _navigateToConnection,
                  ),
                ),
                IconButton(
                  icon: const Icon(Symbols.settings),
                  tooltip: 'Settings',
                  onPressed: widget.onNavigateToSettings,
                ),
                const SizedBox(width: 4),
              ],
            )
          : null,
      bottomNavigationBar: Builder(
        builder: (context) {
          final unread = context.watch<MessageService>().totalUnread;
          return NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _onDestinationSelected,
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            destinations: [
              const NavigationDestination(
                icon: Icon(Symbols.map),
                selectedIcon: Icon(Symbols.map),
                label: 'Map',
              ),
              const NavigationDestination(
                icon: Icon(Symbols.list_alt),
                selectedIcon: Icon(Symbols.list_alt),
                label: 'Log',
              ),
              const NavigationDestination(
                icon: Icon(Symbols.people),
                selectedIcon: Icon(Symbols.people),
                label: 'Stations',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text('$unread'),
                  child: const Icon(Symbols.chat),
                ),
                selectedIcon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text('$unread'),
                  child: const Icon(Symbols.chat),
                ),
                label: 'Messages',
              ),
              const NavigationDestination(
                icon: ConnectionNavIcon(),
                selectedIcon: ConnectionNavIcon(),
                label: 'Connection',
              ),
            ],
          );
        },
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          // Index 0 — Map with FAB cluster.
          Stack(
            children: [
              MeridianMap(
                mapController: widget.mapController,
                markers: widget.markers,
                tileUrl: widget.tileUrl,
                tileProvider: widget.meridianTileProvider.buildTileProvider(),
                connectionStatus: registry.aggregateStatus,
                initialCenter: widget.initialCenter,
                initialZoom: widget.initialZoom,
                northUpLocked: widget.northUpLocked,
                isAnyConnected: registry.isAnyConnected,
                onNotConnectedTap: _navigateToConnection,
                showTracks: widget.showTracks,
                trackPolylines: widget.trackPolylines,
                activeFilterLabel: widget.activeFilterLabel,
                onActiveFilterTap: widget.onOpenFilterPanel,
                visibleStationCount: widget.visibleStationCount,
                totalStationCount: widget.totalStationCount,
                showCountChip: false,
                nearestWxStation: widget.nearestWxStation,
                onMapLongPress: widget.onMapLongPress,
              ),
              // FAB cluster — bottom-right above navigation bar.
              SafeArea(
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16, bottom: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Secondary FABs row.
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Badge(
                              isLabelVisible: widget.isFilterActive,
                              smallSize: 8,
                              child: FloatingActionButton.small(
                                heroTag: 'filter_fab',
                                onPressed: widget.onOpenFilterPanel,
                                tooltip: 'Map filters',
                                child: const Icon(Symbols.filter_list),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FloatingActionButton.small(
                              heroTag: 'north_up_fab',
                              onPressed: widget.onToggleNorthUp,
                              tooltip: widget.northUpLocked
                                  ? 'North Up (locked) — tap to unlock'
                                  : 'Free rotation — tap to lock North Up',
                              child: Icon(
                                widget.northUpLocked
                                    ? Symbols.navigation
                                    : Symbols.explore,
                              ),
                            ),
                            const SizedBox(width: 8),
                            FloatingActionButton.small(
                              heroTag: 'my_station_fab',
                              onPressed: _showOwnStation,
                              tooltip: 'Find my station',
                              child: const Icon(Symbols.person_pin),
                            ),
                            const SizedBox(width: 8),
                            FloatingActionButton.small(
                              heroTag: 'center_fab',
                              onPressed: _locating ? null : _centerOnLocation,
                              tooltip: 'Center on my location',
                              child: _locating
                                  ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator.adaptive(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Symbols.my_location),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Primary beacon FAB.
                        Builder(
                          builder: (ctx) {
                            final beaconing = ctx.watch<BeaconingService>();
                            final reg = ctx.watch<ConnectionRegistry>();
                            final noTarget =
                                beaconing.isActive &&
                                !reg.all.any(
                                  (c) => c.beaconingEnabled && c.isConnected,
                                );
                            return BeaconFAB(
                              isBeaconing: beaconing.isActive,
                              mode: beaconing.mode,
                              lastBeaconAt: beaconing.lastBeaconAt,
                              noBeaconTarget: noTarget,
                              onTap: beaconing.mode == BeaconMode.manual
                                  ? beaconing.beaconNow
                                  : beaconing.isActive
                                  ? beaconing.stopBeaconing
                                  : beaconing.startBeaconing,
                              onLongPress: beaconing.mode == BeaconMode.manual
                                  ? beaconing.beaconNow
                                  : null,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Index 1 — Packet log.
          PacketLogScreen(service: widget.service),

          // Index 2 — Station list.
          StationListScreen(
            service: widget.service,
            onShowOnMap: _showStationOnMap,
          ),

          // Index 3 — Messages.
          const MessagesScreen(),

          // Index 4 — Connection.
          const ConnectionScreen(),
        ],
      ),
    );
  }
}
