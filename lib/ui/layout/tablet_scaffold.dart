import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../services/station_service.dart';
import '../widgets/meridian_bottom_sheet.dart';
import '../widgets/meridian_status_pill.dart';
import 'meridian_map.dart';

/// Tablet (600–1024 px) scaffold: collapsed navigation rail + full map +
/// collapsed bottom panel.
class TabletScaffold extends StatefulWidget {
  const TabletScaffold({
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
  State<TabletScaffold> createState() => _TabletScaffoldState();
}

class _TabletScaffoldState extends State<TabletScaffold> {
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
            status: ConnectionStatus.disconnected,
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
            extended: false,
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
            child: Column(
              children: [
                Expanded(
                  child: MeridianMap(
                    mapController: widget.mapController,
                    markers: widget.markers,
                    tileUrl: widget.tileUrl,
                  ),
                ),
                // Collapsed bottom panel placeholder.
                _BottomPanel(service: widget.service),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({required this.service});

  final StationService service;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 48,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(
            Icons.people,
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
        ],
      ),
    );
  }
}
