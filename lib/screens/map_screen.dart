import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../core/packet/station.dart';
import '../map/meridian_tile_provider.dart';
import '../services/station_service.dart';
import '../services/tnc_service.dart';
import '../services/tx_service.dart';
import '../ui/layout/responsive_layout.dart';
import '../theme/theme_controller.dart';
import '../ui/widgets/aprs_symbol_widget.dart';
import '../ui/utils/platform_route.dart';
import '../ui/widgets/station_info_sheet.dart';
import 'settings_screen.dart';

/// Root screen that owns the [StationService] lifecycle and builds the
/// adaptive layout.
///
/// Map tile URL is theme-aware: light mode uses Stadia `alidade_smooth` tiles,
/// dark mode uses `alidade_smooth_dark`. The theme is read from
/// [ThemeController] and the system brightness is used to resolve
/// [ThemeMode.system].
class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.service,
    required this.tncService,
    this.tileProvider,
    this.callsign = 'NOCALL',
    this.ssid = 0,
    this.initialLat = 39.0,
    this.initialLon = -77.0,
    this.initialZoom = 9.0,
  });

  final StationService service;
  final TncService tncService;

  /// Tile provider with disk cache. When null (e.g. from the onboarding path),
  /// a memory-only fallback is used for the session.
  final MeridianTileProvider? tileProvider;
  final String callsign;

  /// SSID suffix (0 = no suffix, 1–15 appended as `-N`).
  final int ssid;

  final double initialLat;
  final double initialLon;
  final double initialZoom;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late final StationService _service;
  late final MeridianTileProvider _tileProvider;
  final _mapController = MapController();
  List<Marker> _markers = [];
  Timer? _filterDebounce;
  Timer? _markerDebounce;
  // Tracks previous APRS-IS status for the "failed to connect" snackbar only.
  // The build() method reads currentConnectionStatus directly from the service.
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  StreamSubscription<TxEvent>? _txEventSub;
  bool _northUpLocked = true;

  @override
  void initState() {
    super.initState();
    _service = widget.service;
    _tileProvider = widget.tileProvider ?? _UncachedTileProvider();
    _connectionStatus = _service.currentConnectionStatus;
    _service.stationUpdates.listen(_onStationsUpdated);
    // Seed markers from persisted stations already loaded before runApp.
    _onStationsUpdated(_service.currentStations);
    // Track previous APRS-IS status for the "failed to connect" snackbar.
    // The build() method reads currentConnectionStatus directly — this
    // subscription exists only to detect the connecting→disconnected transition.
    _service.connectionState.listen((status) {
      if (!mounted) return;
      final wasConnecting = _connectionStatus == ConnectionStatus.connecting;
      _connectionStatus = status;
      if (wasConnecting && status == ConnectionStatus.disconnected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not connect to APRS-IS. Check your network.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    });
    _service.start().catchError((Object e) {
      debugPrint('APRS-IS connection failed: $e');
    });
    _txEventSub = context.read<TxService>().events.listen(_onTxEvent);
    _mapController.mapEventStream
        .where((e) => e is MapEventMoveEnd)
        .cast<MapEventMoveEnd>()
        .listen(_onMapMoveEnd);
  }

  @override
  void dispose() {
    _filterDebounce?.cancel();
    _markerDebounce?.cancel();
    _txEventSub?.cancel();
    _service.stop();
    _tileProvider.dispose();
    super.dispose();
  }

  void _onTxEvent(TxEvent event) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearMaterialBanners();

    final txService = context.read<TxService>();

    if (event is TxEventTncDisconnected) {
      // Only mention APRS-IS fallback if IS is actually connected.
      final content = txService.aprsIsAvailable
          ? 'TNC disconnected — switched to APRS-IS'
          : 'TNC disconnected';
      // TODO(ios): use Cupertino-styled banner
      messenger.showMaterialBanner(
        MaterialBanner(
          content: Text(content),
          actions: [
            TextButton(
              onPressed: messenger.clearMaterialBanners,
              child: const Text('Dismiss'),
            ),
          ],
        ),
      );
    } else if (event is TxEventTncReconnected) {
      // If APRS-IS is not connected there is no meaningful choice — skip banner.
      if (!txService.aprsIsAvailable) return;
      messenger.showMaterialBanner(
        MaterialBanner(
          content: const Text('TNC connected — switch to RF?'),
          actions: [
            TextButton(
              onPressed: () {
                context.read<TxService>().setPreference(TxTransportPref.tnc);
                messenger.clearMaterialBanners();
              },
              child: const Text('Switch to RF'),
            ),
            TextButton(
              onPressed: messenger.clearMaterialBanners,
              child: const Text('Stay on APRS-IS'),
            ),
          ],
        ),
      );
    }
  }

  void _onMapMoveEnd(MapEventMoveEnd event) {
    _filterDebounce?.cancel();
    _filterDebounce = Timer(const Duration(milliseconds: 800), () {
      final center = event.camera.center;
      final zoom = event.camera.zoom;
      debugPrint('Filter update: ${center.latitude}, ${center.longitude}');
      _service.updateFilter(center.latitude, center.longitude);
      SharedPreferences.getInstance().then((prefs) {
        prefs.setDouble('map_last_lat', center.latitude);
        prefs.setDouble('map_last_lon', center.longitude);
        prefs.setDouble('map_last_zoom', zoom);
      });
    });
  }

  void _onStationsUpdated(Map<String, Station> stations) {
    _markerDebounce?.cancel();
    _markerDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        // Sort ascending by lastHeard so newest stations render on top.
        final sorted = _service.currentStations.values.toList()
          ..sort((a, b) => a.lastHeard.compareTo(b.lastHeard));
        _markers = sorted.map(_buildMarker).toList();
      });
    });
  }

  Marker _buildMarker(Station s) => Marker(
    point: LatLng(s.lat, s.lon),
    width: 44,
    height: 44,
    child: GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        builder: (_) => StationInfoSheet(station: s),
      ),
      child: Tooltip(
        message: s.callsign,
        child: AprsSymbolWidget(
          symbolTable: s.symbolTable,
          symbolCode: s.symbolCode,
          size: 44,
        ),
      ),
    ),
  );

  void _toggleNorthUp() {
    HapticFeedback.lightImpact();
    setState(() => _northUpLocked = !_northUpLocked);
    if (_northUpLocked) _mapController.rotate(0);
  }

  void _navigateToSettings() {
    Navigator.push(context, buildPlatformRoute((_) => const SettingsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    // Watch both services so this widget rebuilds whenever their connection
    // state changes (StationService and TncService both call notifyListeners()
    // on transport state transitions). Reading currentConnectionStatus directly
    // ensures the map always reflects live state regardless of stream ordering.
    final aprsStatus = context.watch<StationService>().currentConnectionStatus;
    final tncStatus = context.watch<TncService>().currentStatus;
    final themeController = context.watch<ThemeController>();
    final brightness = switch (themeController.themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => MediaQuery.of(context).platformBrightness,
    };

    return ResponsiveLayout(
      service: _service,
      tncService: widget.tncService,
      mapController: _mapController,
      markers: _markers,
      tileUrl: _tileProvider.tileUrl(brightness),
      meridianTileProvider: _tileProvider,
      onNavigateToSettings: _navigateToSettings,
      connectionStatus: aprsStatus,
      tncConnectionStatus: tncStatus,
      initialCenter: LatLng(widget.initialLat, widget.initialLon),
      initialZoom: widget.initialZoom,
      northUpLocked: _northUpLocked,
      onToggleNorthUp: _toggleNorthUp,
    );
  }
}

/// Fallback tile provider used when no cached provider is supplied
/// (e.g. the onboarding path or tests). Uses flutter_map's built-in
/// NetworkTileProvider — no Dio client, no lingering timers.
class _UncachedTileProvider implements MeridianTileProvider {
  @override
  String tileUrl(Brightness brightness) {
    final style = brightness == Brightness.dark
        ? 'alidade_smooth_dark'
        : 'alidade_smooth';
    return 'https://tiles.stadiamaps.com/tiles/$style/{z}/{x}/{y}.png'
        '?api_key=${AppConfig.stadiaMapsApiKey}';
  }

  @override
  TileProvider buildTileProvider() => NetworkTileProvider();

  @override
  void dispose() {}
}
