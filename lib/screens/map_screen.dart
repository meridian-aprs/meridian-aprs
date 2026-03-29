import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/packet/station.dart';
import '../services/station_service.dart';
import '../services/tnc_service.dart';
import '../services/tx_service.dart';
import '../ui/layout/responsive_layout.dart';
import '../theme/meridian_colors.dart';
import '../theme/theme_controller.dart';
import '../ui/widgets/aprs_symbol_widget.dart';
import '../ui/widgets/station_info_sheet.dart';
import 'settings_screen.dart';

/// Root screen that owns the [StationService] lifecycle and builds the
/// adaptive layout.
///
/// Map tile URL is theme-aware: light mode uses OSM standard tiles, dark mode
/// uses CartoDB dark tiles. The theme is read from [ThemeController] and the
/// system brightness is used to resolve [ThemeMode.system].
class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.service,
    required this.tncService,
    this.callsign = 'NOCALL',
    this.ssid = 0,
    this.initialLat = 39.0,
    this.initialLon = -77.0,
    this.initialZoom = 9.0,
  });

  final StationService service;
  final TncService tncService;
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
  final _mapController = MapController();
  List<Marker> _markers = [];
  Timer? _filterDebounce;
  Timer? _markerDebounce;
  late ConnectionStatus _connectionStatus;
  ConnectionStatus _tncConnectionStatus = ConnectionStatus.disconnected;
  StreamSubscription<ConnectionStatus>? _tncStatusSub;
  StreamSubscription<TxEvent>? _txEventSub;
  bool _northUpLocked = true;

  // Tile URL constants.
  static const _lightTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const _darkTileUrl =
      'https://cartodb-basemaps-{s}.global.ssl.fastly.net/dark_all/{z}/{x}/{y}.png';

  @override
  void initState() {
    super.initState();
    _service = widget.service;
    _connectionStatus = _service.currentConnectionStatus;
    _service.stationUpdates.listen(_onStationsUpdated);
    // Seed markers from persisted stations already loaded before runApp.
    _onStationsUpdated(_service.currentStations);
    _service.connectionState.listen((status) {
      if (!mounted) return;
      final wasConnecting = _connectionStatus == ConnectionStatus.connecting;
      setState(() => _connectionStatus = status);
      if (wasConnecting && status == ConnectionStatus.disconnected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not connect to APRS-IS. Check your network.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    });
    _tncStatusSub = widget.tncService.connectionState.listen((status) {
      if (!mounted) return;
      setState(() => _tncConnectionStatus = status);
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
    _tncStatusSub?.cancel();
    _txEventSub?.cancel();
    _service.stop();
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

  /// Returns an icon color appropriate for the APRS symbol code.
  Color _markerColor(String symbolCode) {
    switch (symbolCode) {
      // Emergency / police / fire
      case '!':
      case 'P':
      case 'f':
      case 'd':
        return MeridianColors.danger;
      // Weather
      case '_':
        return MeridianColors.signal;
      default:
        return MeridianColors.primary;
    }
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
          color: _markerColor(s.symbolCode),
        ),
      ),
    ),
  );

  /// Resolve the tile URL based on the current theme mode and system brightness.
  String _tileUrl(BuildContext context) {
    final themeController = context.watch<ThemeController>();
    final brightness = switch (themeController.themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => MediaQuery.of(context).platformBrightness,
    };
    return brightness == Brightness.dark ? _darkTileUrl : _lightTileUrl;
  }

  void _toggleNorthUp() {
    HapticFeedback.lightImpact();
    setState(() => _northUpLocked = !_northUpLocked);
    if (_northUpLocked) _mapController.rotate(0);
  }

  void _navigateToSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      service: _service,
      tncService: widget.tncService,
      mapController: _mapController,
      markers: _markers,
      tileUrl: _tileUrl(context),
      onNavigateToSettings: _navigateToSettings,
      connectionStatus: _connectionStatus,
      tncConnectionStatus: _tncConnectionStatus,
      initialCenter: LatLng(widget.initialLat, widget.initialLon),
      initialZoom: widget.initialZoom,
      northUpLocked: _northUpLocked,
      onToggleNorthUp: _toggleNorthUp,
    );
  }
}
