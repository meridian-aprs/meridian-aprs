import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../screens/packet_log_screen.dart';
import '../../services/station_service.dart';
import '../widgets/beacon_fab.dart';
import '../widgets/meridian_bottom_sheet.dart';
import '../widgets/meridian_status_pill.dart';
import 'meridian_map.dart';

/// Mobile (< 600 px) scaffold: full-screen map, FAB cluster, bottom sheets.
///
/// The map canvas fills the entire body. FABs are overlaid in the bottom-right
/// corner using a [Stack]. The existing packet log FAB is available via the
/// app bar actions to keep the core screen uncluttered.
class MobileScaffold extends StatelessWidget {
  const MobileScaffold({
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
            onPressed: onNavigateToSettings,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          MeridianMap(
            mapController: mapController,
            markers: markers,
            tileUrl: tileUrl,
          ),
          // FAB cluster — bottom-right above system navigation bar.
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
                          heroTag: 'search_fab',
                          onPressed: () {},
                          tooltip: 'Search callsign',
                          child: const Icon(Icons.search),
                        ),
                        const SizedBox(width: 8),
                        FloatingActionButton.small(
                          heroTag: 'center_fab',
                          onPressed: () {},
                          tooltip: 'Center on my location',
                          child: const Icon(Icons.my_location),
                        ),
                        const SizedBox(width: 8),
                        FloatingActionButton.small(
                          heroTag: 'packet_log_fab',
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PacketLogScreen(service: service),
                            ),
                          ),
                          tooltip: 'Packet Log',
                          child: const Icon(Icons.list_alt),
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
