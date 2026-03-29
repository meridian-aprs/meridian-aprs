import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:provider/provider.dart';

import '../../screens/connection_screen.dart';
import '../../screens/messages_screen.dart';
import '../../screens/packet_log_screen.dart';
import '../../screens/station_list_screen.dart';
import '../../services/message_service.dart';
import '../../services/station_service.dart';
import '../../services/tnc_service.dart';
import '../widgets/connection_nav_icon.dart';
import '../widgets/meridian_status_pill.dart';
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
  State<TabletScaffold> createState() => _TabletScaffoldState();
}

class _TabletScaffoldState extends State<TabletScaffold> {
  // Indices 0-4 correspond to Map, Log, Stations, Messages, Connection.
  int _selectedIndex = 0;

  void _navigateToConnection() {
    setState(() => _selectedIndex = 4);
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
            onTap: _navigateToConnection,
          ),
          if (!kIsWeb &&
              (Platform.isLinux || Platform.isMacOS || Platform.isWindows))
            MeridianStatusPill(
              label: 'TNC',
              status: widget.tncConnectionStatus,
              onTap: _navigateToConnection,
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
                        connectionStatus: widget.connectionStatus,
                        initialCenter: widget.initialCenter,
                        initialZoom: widget.initialZoom,
                        northUpLocked: widget.northUpLocked,
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
                StationListScreen(service: widget.service),

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
