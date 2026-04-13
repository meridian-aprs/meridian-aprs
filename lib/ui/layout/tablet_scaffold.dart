import 'package:flutter/material.dart';
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
import '../../services/message_service.dart';
import '../../services/station_service.dart';
import '../../services/station_settings_service.dart';
import '../widgets/connection_nav_icon.dart';
import '../widgets/meridian_status_pill.dart';
import '../widgets/station_info_sheet.dart';
import 'meridian_map.dart';

/// Tablet (600–1024 px) scaffold: collapsed navigation rail + full map +
/// collapsed bottom panel.
///
/// The [NavigationRail] provides in-place tab switching via [IndexedStack]
/// for Map, Log, Stations, Messages, and Connection. Settings pushes a
/// full-screen route.
class TabletScaffold extends StatefulWidget {
  const TabletScaffold({
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
  State<TabletScaffold> createState() => _TabletScaffoldState();
}

class _TabletScaffoldState extends State<TabletScaffold> {
  // Indices 0-4 correspond to Map, Log, Stations, Messages, Connection.
  int _selectedIndex = 0;
  bool _locating = false;

  void _navigateToConnection() {
    setState(() => _selectedIndex = 4);
  }

  Future<void> _centerOnLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
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
      appBar: AppBar(
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
            icon: Icon(
              widget.northUpLocked ? Symbols.navigation : Symbols.explore,
            ),
            tooltip: widget.northUpLocked
                ? 'North Up (locked) — tap to unlock'
                : 'Free rotation — tap to lock North Up',
            onPressed: widget.onToggleNorthUp,
          ),
          Badge(
            isLabelVisible: widget.isFilterActive,
            smallSize: 8,
            child: IconButton(
              icon: const Icon(Symbols.filter_list),
              tooltip: 'Map filters',
              onPressed: widget.onOpenFilterPanel,
            ),
          ),
          IconButton(
            icon: const Icon(Symbols.person_pin),
            tooltip: 'Find my station',
            onPressed: _showOwnStation,
          ),
          IconButton(
            icon: _locating
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  )
                : const Icon(Symbols.my_location),
            tooltip: 'Center on my location',
            onPressed: _locating ? null : _centerOnLocation,
          ),
          IconButton(
            icon: const Icon(Symbols.settings),
            tooltip: 'Settings',
            onPressed: widget.onNavigateToSettings,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            extended: false,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) {
              if (i == 5) {
                widget.onNavigateToSettings();
                return;
              }
              setState(() => _selectedIndex = i);
            },
            destinations: [
              const NavigationRailDestination(
                icon: Icon(Symbols.map),
                selectedIcon: Icon(Symbols.map),
                label: Text('Map'),
              ),
              const NavigationRailDestination(
                icon: Icon(Symbols.list_alt),
                selectedIcon: Icon(Symbols.list_alt),
                label: Text('Log'),
              ),
              const NavigationRailDestination(
                icon: Icon(Symbols.people),
                selectedIcon: Icon(Symbols.people),
                label: Text('Stations'),
              ),
              NavigationRailDestination(
                icon: Builder(
                  builder: (ctx) {
                    final unread = ctx.watch<MessageService>().totalUnread;
                    return Badge(
                      isLabelVisible: unread > 0,
                      label: Text('$unread'),
                      child: const Icon(Symbols.chat),
                    );
                  },
                ),
                selectedIcon: const Icon(Symbols.chat),
                label: const Text('Messages'),
              ),
              const NavigationRailDestination(
                icon: ConnectionNavIcon(),
                selectedIcon: ConnectionNavIcon(),
                label: Text('Connection'),
              ),
              const NavigationRailDestination(
                icon: Icon(Symbols.settings),
                selectedIcon: Icon(Symbols.settings),
                label: Text('Settings'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                // Index 0 — Map with collapsible bottom panel.
                Column(
                  children: [
                    Expanded(
                      child: MeridianMap(
                        mapController: widget.mapController,
                        markers: widget.markers,
                        tileUrl: widget.tileUrl,
                        tileProvider: widget.meridianTileProvider
                            .buildTileProvider(),
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
                        nearestWxStation: widget.nearestWxStation,
                        onMapLongPress: widget.onMapLongPress,
                      ),
                    ),
                    // Collapsed bottom panel — tapping switches to the Log tab.
                    _BottomPanel(
                      service: widget.service,
                      onTap: () => setState(() => _selectedIndex = 1),
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
          ),
        ],
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({required this.service, required this.onTap});

  final StationService service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 48,
        color: theme.colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(
              Symbols.people,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              '${service.currentStations.length} stations nearby',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Icon(
              Symbols.expand_less,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
