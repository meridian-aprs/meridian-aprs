import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../core/packet/station.dart';
import '../../screens/connection_screen.dart';
import '../../screens/messages_screen.dart';
import '../../screens/packet_log_screen.dart';
import '../../screens/station_list_screen.dart';
import '../../services/beaconing_service.dart';
import '../../services/message_service.dart';
import '../../services/station_service.dart';
import '../../services/tnc_service.dart';
import '../widgets/beacon_fab.dart';
import '../widgets/connection_nav_icon.dart';
import '../widgets/meridian_status_pill.dart';
import '../widgets/station_search_delegate.dart';
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
    required this.tncService,
    required this.mapController,
    required this.markers,
    required this.tileUrl,
    required this.onNavigateToSettings,
    this.connectionStatus = ConnectionStatus.disconnected,
    this.tncConnectionStatus = ConnectionStatus.disconnected,
    this.initialCenter = const LatLng(39.0, -77.0),
    this.initialZoom = 9.0,
    this.northUpLocked = true,
    required this.onToggleNorthUp,
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
  final bool northUpLocked;
  final VoidCallback onToggleNorthUp;

  @override
  State<MobileScaffold> createState() => _MobileScaffoldState();
}

class _MobileScaffoldState extends State<MobileScaffold> {
  int _selectedIndex = 0;
  bool _locating = false;

  static String _tncPillLabel(TransportType type) => switch (type) {
    TransportType.ble => 'BLE TNC',
    TransportType.serial => 'USB TNC',
    TransportType.none => 'TNC',
  };

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

  Future<void> _searchCallsign() async {
    // TODO(ios): replace with Cupertino search UI once iOS theme is validated
    final station = await showSearch<Station?>(
      context: context,
      delegate: StationSearchDelegate(stations: widget.service.currentStations),
    );
    if (station != null && mounted) {
      setState(() => _selectedIndex = 0);
      widget.mapController.move(LatLng(station.lat, station.lon), 13.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _selectedIndex == 0
          ? AppBar(
              title: const Text('Meridian'),
              actions: [
                MeridianStatusPill(
                  status: widget.connectionStatus,
                  label: 'APRS-IS',
                  onTap: _navigateToConnection,
                ),
                if (!kIsWeb &&
                    (widget.tncConnectionStatus !=
                            ConnectionStatus.disconnected ||
                        widget.tncService.activeTransportType !=
                            TransportType.none))
                  MeridianStatusPill(
                    label: _tncPillLabel(widget.tncService.activeTransportType),
                    status: widget.tncConnectionStatus,
                    onTap: _navigateToConnection,
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
                connectionStatus: widget.connectionStatus,
                initialCenter: widget.initialCenter,
                initialZoom: widget.initialZoom,
                northUpLocked: widget.northUpLocked,
                isAnyConnected:
                    widget.connectionStatus == ConnectionStatus.connected ||
                    widget.tncConnectionStatus == ConnectionStatus.connected,
                onNotConnectedTap: _navigateToConnection,
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
                              heroTag: 'search_fab',
                              onPressed: _searchCallsign,
                              tooltip: 'Search callsign',
                              child: const Icon(Symbols.search),
                            ),
                            const SizedBox(width: 8),
                            FloatingActionButton.small(
                              heroTag: 'center_fab',
                              onPressed: _locating ? null : _centerOnLocation,
                              tooltip: 'Center on my location',
                              child: _locating
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
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
                            return BeaconFAB(
                              isBeaconing: beaconing.isActive,
                              mode: beaconing.mode,
                              lastBeaconAt: beaconing.lastBeaconAt,
                              onTap: beaconing.beaconNow,
                              onLongPress: beaconing.beaconNow,
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
          StationListScreen(service: widget.service),

          // Index 3 — Messages.
          const MessagesScreen(),

          // Index 4 — Connection.
          const ConnectionScreen(),
        ],
      ),
    );
  }
}
