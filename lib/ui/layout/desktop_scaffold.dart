import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../screens/packet_log_screen.dart';
import '../../screens/station_list_screen.dart';
import '../../services/station_service.dart';
import '../../services/tnc_service.dart';
import '../widgets/connection_sheet.dart';
import '../widgets/meridian_bottom_sheet.dart';
import '../widgets/meridian_status_pill.dart';
import 'meridian_map.dart';

/// Desktop (> 1024 px) scaffold: expanded navigation rail (240 px) + map +
/// side panel.
class DesktopScaffold extends StatefulWidget {
  const DesktopScaffold({
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
  State<DesktopScaffold> createState() => _DesktopScaffoldState();
}

class _DesktopScaffoldState extends State<DesktopScaffold> {
  int _selectedIndex = 0;
  bool _navRailExpanded = true;
  bool _panelVisible = true;

  void _showConnectionSheet(BuildContext context) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Symbols.menu),
          tooltip: _navRailExpanded ? 'Collapse sidebar' : 'Expand sidebar',
          onPressed: () => setState(() => _navRailExpanded = !_navRailExpanded),
        ),
        title: const Text('Meridian'),
        actions: [
          MeridianStatusPill(
            status: widget.connectionStatus,
            label: 'APRS-IS',
            onTap: () => _showConnectionSheet(context),
          ),
          if (!kIsWeb &&
              (Platform.isLinux || Platform.isMacOS || Platform.isWindows))
            MeridianStatusPill(
              label: 'TNC',
              status: widget.tncConnectionStatus,
              onTap: () => _showConnectionSheet(context),
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
          IconButton(
            icon: Icon(
              _panelVisible ? Symbols.view_sidebar : Symbols.view_sidebar,
            ),
            tooltip: _panelVisible ? 'Hide packet log' : 'Show packet log',
            onPressed: () => setState(() => _panelVisible = !_panelVisible),
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
            extended: _navRailExpanded,
            minExtendedWidth: 240,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) {
              if (i == 1) {
                // Stations — push full-screen station list.
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => StationListScreen(service: widget.service),
                  ),
                );
              } else if (i == 3) {
                // Connection — transient action; open sheet without updating
                // the persistent rail selection.
                _showConnectionSheet(context);
                return;
              } else if (i == 4) {
                widget.onNavigateToSettings();
              } else {
                setState(() => _selectedIndex = i);
              }
            },
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Symbols.map),
                selectedIcon: Icon(Symbols.map),
                label: Text('Map'),
              ),
              NavigationRailDestination(
                icon: Icon(Symbols.people),
                selectedIcon: Icon(Symbols.people),
                label: Text('Stations'),
              ),
              NavigationRailDestination(
                icon: Icon(Symbols.chat),
                selectedIcon: Icon(Symbols.chat),
                label: Text('Messages'),
              ),
              NavigationRailDestination(
                icon: Icon(Symbols.router),
                selectedIcon: Icon(Symbols.router),
                label: Text('Connection'),
              ),
              NavigationRailDestination(
                icon: Icon(Symbols.settings),
                selectedIcon: Icon(Symbols.settings),
                label: Text('Settings'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: MeridianMap(
              mapController: widget.mapController,
              markers: widget.markers,
              tileUrl: widget.tileUrl,
              connectionStatus: widget.connectionStatus,
              initialCenter: widget.initialCenter,
              initialZoom: widget.initialZoom,
              northUpLocked: widget.northUpLocked,
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: _panelVisible
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const VerticalDivider(width: 1),
                      _PacketLogPanel(service: widget.service),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _PacketLogPanel extends StatelessWidget {
  const _PacketLogPanel({required this.service});

  final StationService service;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              'Packet Log',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const Divider(height: 1),
          Expanded(child: PacketLogBody(service: service)),
        ],
      ),
    );
  }
}
