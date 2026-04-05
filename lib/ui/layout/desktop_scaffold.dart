import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:provider/provider.dart';

import '../../map/meridian_tile_provider.dart';

import '../../core/packet/station.dart';
import '../../screens/connection_screen.dart';
import '../../screens/location_picker_screen.dart';
import '../../screens/messages_screen.dart';
import '../../screens/packet_log_screen.dart';
import '../../screens/station_list_screen.dart';
import '../../services/beaconing_service.dart';
import '../../services/message_service.dart';
import '../../services/station_service.dart';
import '../../services/tnc_service.dart';
import '../../services/tx_service.dart';
import '../../theme/meridian_colors.dart';
import '../widgets/connection_nav_icon.dart';
import '../utils/platform_route.dart';
import '../widgets/station_search_delegate.dart';
import 'meridian_map.dart';

/// Desktop (> 1024 px) scaffold: expanded navigation rail (240 px) + map +
/// side panel.
///
/// The [NavigationRail] provides in-place tab switching via [IndexedStack]
/// for Map, Stations, Messages, and Connection. Settings pushes a full-screen
/// route.
class DesktopScaffold extends StatefulWidget {
  const DesktopScaffold({
    super.key,
    required this.service,
    required this.tncService,
    required this.mapController,
    required this.markers,
    required this.tileUrl,
    required this.meridianTileProvider,
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
  final MeridianTileProvider meridianTileProvider;
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
  // Indices 0-3 correspond to Map, Stations, Messages, Connection.
  int _selectedIndex = 0;
  bool _navRailExpanded = true;
  bool _panelVisible = true;
  bool _locating = false;

  void _navigateToConnection() {
    setState(() => _selectedIndex = 3);
  }

  Future<void> _centerOnLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      // Try GPS first — works on macOS (Core Location) and may work on some
      // Linux setups. Falls back to the address picker when unavailable.
      try {
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (serviceEnabled) {
          LocationPermission permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
          }
          if (permission != LocationPermission.denied &&
              permission != LocationPermission.deniedForever) {
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
            return;
          }
        }
      } on UnimplementedError {
        // No geolocator implementation on this platform (e.g. Linux) — fall
        // through to the address picker below.
      } catch (_) {
        // Any other GPS error — fall through to the address picker.
      }

      // GPS unavailable or denied: open the address/map picker instead.
      if (!mounted) return;
      final result = await Navigator.push<LatLng>(
        context,
        buildPlatformRoute((_) => const LocationPickerScreen()),
      );
      if (result != null && mounted) {
        widget.mapController.move(result, 13.0);
      }
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
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Symbols.menu),
          tooltip: _navRailExpanded ? 'Collapse sidebar' : 'Expand sidebar',
          onPressed: () => setState(() => _navRailExpanded = !_navRailExpanded),
        ),
        title: const Text('Meridian'),
        actions: [
          _ConnectionStatusChip(onTap: _navigateToConnection),
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
          _BeaconToolbarButton(),
          IconButton(
            icon: const Icon(Symbols.search),
            tooltip: 'Search callsign',
            onPressed: _searchCallsign,
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
            extended: _navRailExpanded,
            minExtendedWidth: 240,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) {
              if (i == 4) {
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
                // Index 0 — Map with optional side packet log panel.
                Row(
                  children: [
                    Expanded(
                      child: MeridianMap(
                        mapController: widget.mapController,
                        markers: widget.markers,
                        tileUrl: widget.tileUrl,
                        tileProvider: widget.meridianTileProvider
                            .buildTileProvider(),
                        connectionStatus: widget.connectionStatus,
                        initialCenter: widget.initialCenter,
                        initialZoom: widget.initialZoom,
                        northUpLocked: widget.northUpLocked,
                        isAnyConnected:
                            widget.connectionStatus ==
                                ConnectionStatus.connected ||
                            widget.tncConnectionStatus ==
                                ConnectionStatus.connected,
                        onNotConnectedTap: _navigateToConnection,
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

                // Index 1 — Station list.
                StationListScreen(service: widget.service),

                // Index 2 — Messages.
                const MessagesScreen(),

                // Index 3 — Connection.
                const ConnectionScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact connection status chip for the desktop AppBar.
///
/// Shows combined APRS-IS + TNC state in a single [ActionChip]. Tapping
/// navigates to the Connection screen.
class _ConnectionStatusChip extends StatelessWidget {
  const _ConnectionStatusChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Selector2<
      StationService,
      TncService,
      (ConnectionStatus, ConnectionStatus)
    >(
      selector: (_, ss, tnc) => (ss.currentConnectionStatus, tnc.currentStatus),
      builder: (context, statuses, _) {
        final (aprsStatus, tncStatus) = statuses;
        final aprsConnected = aprsStatus == ConnectionStatus.connected;
        final tncConnected = tncStatus == ConnectionStatus.connected;
        final anyError =
            aprsStatus == ConnectionStatus.error ||
            tncStatus == ConnectionStatus.error;
        final anyConnecting =
            aprsStatus == ConnectionStatus.connecting ||
            tncStatus == ConnectionStatus.connecting;

        final String label;
        final Color color;
        if (aprsConnected && tncConnected) {
          label = 'APRS-IS + TNC';
          color = MeridianColors.signal;
        } else if (aprsConnected) {
          label = 'APRS-IS';
          color = MeridianColors.signal;
        } else if (tncConnected) {
          label = 'TNC';
          color = MeridianColors.signal;
        } else if (anyError) {
          label = 'Error';
          color = MeridianColors.warning;
        } else if (anyConnecting) {
          label = 'Connecting\u2026';
          color = MeridianColors.warning;
        } else {
          label = 'Not connected';
          color = Theme.of(context).colorScheme.onSurfaceVariant;
        }

        return ActionChip(
          avatar: Icon(Symbols.router, size: 16, color: color),
          label: Text(label),
          labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
          onPressed: onTap,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 4),
        );
      },
    );
  }
}

/// Compact beacon toolbar button for the desktop AppBar.
///
/// Shows a filled icon when actively beaconing (auto/smart), a plain icon when
/// idle or in manual mode. In manual mode tapping fires [BeaconingService.beaconNow];
/// in auto/smart mode tapping toggles [BeaconingService.startBeaconing] /
/// [BeaconingService.stopBeaconing].
class _BeaconToolbarButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final svc = context.watch<BeaconingService>();
    final tx = context.watch<TxService>();
    final isActive = svc.isActive;
    final noTarget =
        isActive &&
        !(tx.beaconToAprsIs && tx.aprsIsAvailable) &&
        !(tx.beaconToTnc && tx.tncAvailable);
    final tooltip = noTarget
        ? 'Beaconing active — no TX path (enable in Connection)'
        : switch (svc.mode) {
            BeaconMode.auto =>
              isActive ? 'Stop auto beaconing' : 'Start auto beaconing',
            BeaconMode.smart =>
              isActive ? 'Stop SmartBeaconing™' : 'Start SmartBeaconing™',
            BeaconMode.manual => 'Send beacon now',
          };
    return IconButton(
      icon: Badge(
        isLabelVisible: noTarget,
        backgroundColor: MeridianColors.warning,
        smallSize: 8,
        child: Icon(
          Symbols.cell_tower,
          color: isActive ? MeridianColors.danger : null,
        ),
      ),
      tooltip: tooltip,
      onPressed: svc.mode == BeaconMode.manual
          ? svc.beaconNow
          : isActive
          ? svc.stopBeaconing
          : svc.startBeaconing,
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
