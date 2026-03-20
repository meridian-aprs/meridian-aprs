import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/station_service.dart';
import '../widgets/meridian_bottom_sheet.dart';
import '../widgets/meridian_status_pill.dart';
import 'meridian_map.dart';

/// Desktop (> 1024 px) scaffold: expanded navigation rail (240 px) + map +
/// side panel.
class DesktopScaffold extends StatefulWidget {
  const DesktopScaffold({
    super.key,
    required this.service,
    required this.mapController,
    required this.markers,
    required this.tileUrl,
    required this.onNavigateToSettings,
    this.connectionStatus = ConnectionStatus.disconnected,
    this.initialCenter = const LatLng(39.0, -77.0),
    this.initialZoom = 9.0,
  });

  final StationService service;
  final MapController mapController;
  final List<Marker> markers;
  final String tileUrl;
  final VoidCallback onNavigateToSettings;
  final ConnectionStatus connectionStatus;
  final LatLng initialCenter;
  final double initialZoom;

  @override
  State<DesktopScaffold> createState() => _DesktopScaffoldState();
}

class _DesktopScaffoldState extends State<DesktopScaffold> {
  int _selectedIndex = 0;

  void _showConnectionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => MeridianBottomSheet(
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Connection settings coming soon'),
          ),
        ),
      ),
    );
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
            onTap: () => _showConnectionSheet(context),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: widget.onNavigateToSettings,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            extended: true,
            minExtendedWidth: 240,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) {
              if (i == 4) {
                widget.onNavigateToSettings();
              } else {
                setState(() => _selectedIndex = i);
              }
            },
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.map_outlined),
                selectedIcon: Icon(Icons.map),
                label: Text('Map'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: Text('Stations'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.message_outlined),
                selectedIcon: Icon(Icons.message),
                label: Text('Messages'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.router_outlined),
                selectedIcon: Icon(Icons.router),
                label: Text('Connection'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
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
              initialCenter: widget.initialCenter,
              initialZoom: widget.initialZoom,
            ),
          ),
          const VerticalDivider(width: 1),
          // Side panel — packet log / station list panel (future).
          const _SidePanel(),
        ],
      ),
    );
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 320,
      child: Container(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Packet Log / Stations panel coming soon',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
