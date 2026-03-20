import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/packet/station.dart';
import '../core/transport/aprs_is_transport.dart';
import '../core/transport/aprs_transport.dart';
import '../services/station_service.dart';
import '../ui/layout/responsive_layout.dart';
import '../ui/theme/app_theme.dart';
import '../ui/theme/theme_provider.dart';
import '../ui/widgets/aprs_symbol_widget.dart';
import '../ui/widgets/station_info_sheet.dart';
import 'settings_screen.dart';

/// Root screen that owns the [StationService] lifecycle and builds the
/// adaptive layout.
///
/// Map tile URL is theme-aware: light mode uses OSM standard tiles, dark mode
/// uses CartoDB dark tiles. The theme is read from [ThemeProvider] and the
/// system brightness is used to resolve [ThemeMode.system].
class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    this.callsign = 'NOCALL',
    this.initialLat = 39.0,
    this.initialLon = -77.0,
    this.initialZoom = 9.0,
  });

  final String callsign;
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
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;

  // Tile URL constants.
  static const _lightTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const _darkTileUrl =
      'https://cartodb-basemaps-{s}.global.ssl.fastly.net/dark_all/{z}/{x}/{y}.png';

  @override
  void initState() {
    super.initState();
    final callsign =
        widget.callsign.isNotEmpty ? widget.callsign : 'NOCALL';
    final transport = AprsIsTransport(
      loginLine: 'user $callsign pass -1 vers meridian-aprs 0.1\r\n',
      filterLine:
          '#filter r/${widget.initialLat.toStringAsFixed(1)}/${widget.initialLon.toStringAsFixed(1)}/100\r\n',
    );
    _service = StationService(transport);
    _service.stationUpdates.listen(_onStationsUpdated);
    _service.connectionState.listen((status) {
      if (mounted) setState(() => _connectionStatus = status);
    });
    _service.start().catchError((Object e) {
      debugPrint('APRS-IS connection failed: $e');
    });
    _mapController.mapEventStream
        .where((e) => e is MapEventMoveEnd)
        .cast<MapEventMoveEnd>()
        .listen(_onMapMoveEnd);
  }

  @override
  void dispose() {
    _filterDebounce?.cancel();
    _markerDebounce?.cancel();
    _service.stop();
    super.dispose();
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
        _markers = _service.currentStations.values.map(_buildMarker).toList();
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
        return AppColors.danger;
      // Weather
      case '_':
        return AppColors.accent;
      default:
        return AppColors.primaryLight;
    }
  }

  Marker _buildMarker(Station s) => Marker(
    point: LatLng(s.lat, s.lon),
    width: 36,
    height: 36,
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
          size: 36,
          color: _markerColor(s.symbolCode),
        ),
      ),
    ),
  );

  /// Resolve the tile URL based on the current theme mode and system brightness.
  String _tileUrl(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final brightness = switch (themeProvider.themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => MediaQuery.of(context).platformBrightness,
    };
    return brightness == Brightness.dark ? _darkTileUrl : _lightTileUrl;
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
      mapController: _mapController,
      markers: _markers,
      tileUrl: _tileUrl(context),
      onNavigateToSettings: _navigateToSettings,
      connectionStatus: _connectionStatus,
      initialCenter: LatLng(widget.initialLat, widget.initialLon),
      initialZoom: widget.initialZoom,
    );
  }
}
