import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../screens/packet_log_screen.dart';
import '../../screens/station_list_screen.dart';
import '../../services/station_service.dart';
import '../../services/tnc_service.dart';
import '../widgets/beacon_fab.dart';
import '../widgets/connection_sheet.dart';
import '../widgets/meridian_bottom_sheet.dart';
import '../widgets/meridian_status_pill.dart';
import 'meridian_map.dart';

/// Mobile (< 600 px) scaffold: full-screen map, FAB cluster, M3 Navigation Bar.
///
/// The [NavigationBar] at the bottom provides access to all primary
/// destinations. Tapping a non-map destination pushes the corresponding screen
/// and highlights that destination while it is open; returning pops back to the
/// map and resets the selection.
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

  static String _tncPillLabel(TransportType type) => switch (type) {
    TransportType.ble => 'BLE TNC',
    TransportType.serial => 'USB TNC',
    TransportType.none => 'TNC',
  };

  void _showConnectionSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => MeridianBottomSheet(
        child: ConnectionSheet(
          stationService: widget.service,
          tncService: widget.tncService,
        ),
      ),
    );
  }

  void _onDestinationSelected(int index) {
    if (index == 0) return; // already on map

    HapticFeedback.selectionClick();
    setState(() => _selectedIndex = index);

    final route = switch (index) {
      1 => MaterialPageRoute<void>(
        builder: (_) => PacketLogScreen(service: widget.service),
      ),
      2 => MaterialPageRoute<void>(
        builder: (_) => StationListScreen(service: widget.service),
      ),
      _ => null,
    };

    if (route != null) {
      Navigator.push(context, route).then((_) {
        if (mounted) setState(() => _selectedIndex = 0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meridian'),
        actions: [
          MeridianStatusPill(
            status: widget.connectionStatus,
            label: 'APRS-IS',
            onTap: _showConnectionSheet,
          ),
          if (!kIsWeb &&
              (widget.tncConnectionStatus != ConnectionStatus.disconnected ||
                  widget.tncService.activeTransportType !=
                      TransportType.none))
            MeridianStatusPill(
              label: _tncPillLabel(widget.tncService.activeTransportType),
              status: widget.tncConnectionStatus,
              onTap: _showConnectionSheet,
            ),
          IconButton(
            icon: const Icon(Symbols.settings),
            tooltip: 'Settings',
            onPressed: widget.onNavigateToSettings,
          ),
          const SizedBox(width: 4),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onDestinationSelected,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Symbols.map),
            selectedIcon: Icon(Symbols.map),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Symbols.list_alt),
            selectedIcon: Icon(Symbols.list_alt),
            label: 'Log',
          ),
          NavigationDestination(
            icon: Icon(Symbols.people),
            selectedIcon: Icon(Symbols.people),
            label: 'Stations',
          ),
          NavigationDestination(
            icon: Icon(Symbols.chat),
            selectedIcon: Icon(Symbols.chat),
            label: 'Messages',
          ),
        ],
      ),
      body: Stack(
        children: [
          MeridianMap(
            mapController: widget.mapController,
            markers: widget.markers,
            tileUrl: widget.tileUrl,
            connectionStatus: widget.connectionStatus,
            initialCenter: widget.initialCenter,
            initialZoom: widget.initialZoom,
            northUpLocked: widget.northUpLocked,
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
                          onPressed: () {},
                          tooltip: 'Search callsign',
                          child: const Icon(Symbols.search),
                        ),
                        const SizedBox(width: 8),
                        FloatingActionButton.small(
                          heroTag: 'center_fab',
                          onPressed: () {},
                          tooltip: 'Center on my location',
                          child: const Icon(Symbols.my_location),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Primary beacon FAB.
                    BeaconFAB(isBeaconing: false, onTap: () {}),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
