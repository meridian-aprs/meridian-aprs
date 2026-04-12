import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../core/connection/aprs_is_connection.dart';
import '../core/connection/connection_registry.dart';
import '../core/packet/station.dart';
import '../map/meridian_tile_provider.dart';
import '../services/station_service.dart';
import '../services/tx_service.dart';
import '../ui/layout/responsive_layout.dart';
import '../ui/widgets/map_filter_panel.dart';
import '../theme/theme_controller.dart';
import '../ui/widgets/aprs_symbol_widget.dart';
import '../ui/utils/platform_route.dart';
import '../ui/widgets/meridian_bottom_sheet.dart';
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
    this.tileProvider,
    this.callsign = 'NOCALL',
    this.ssid = 0,
    this.initialLat = 39.0,
    this.initialLon = -77.0,
    this.initialZoom = 9.0,
  });

  final StationService service;

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
  List<Polyline> _trackPolylines = [];
  Timer? _filterDebounce;
  Timer? _markerDebounce;
  StreamSubscription<TxEvent>? _txEventSub;
  bool _northUpLocked = true;
  bool _showTracks = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service;
    _tileProvider = widget.tileProvider ?? _UncachedTileProvider();
    _service.stationUpdates.listen(_onStationsUpdated);
    // Rebuild markers when the display filter setting changes (notifyListeners).
    _service.addListener(_onServiceSettingChanged);
    // Seed markers from persisted stations already loaded before runApp.
    _onStationsUpdated(_service.currentStations);
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
    _service.removeListener(_onServiceSettingChanged);
    _tileProvider.dispose();
    super.dispose();
  }

  /// Called when [StationService] notifies — e.g. when [stationMaxAgeMinutes]
  /// changes. Rebuilds markers so the display filter takes effect immediately.
  void _onServiceSettingChanged() {
    _onStationsUpdated(_service.currentStations);
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
    _filterDebounce = Timer(const Duration(milliseconds: 500), () {
      final camera = event.camera;
      final center = camera.center;
      final zoom = camera.zoom;
      debugPrint('Filter update: bounds=${camera.visibleBounds}');
      final aprsIsConn = context.read<ConnectionRegistry>().byId('aprs_is');
      if (aprsIsConn is AprsIsConnection) {
        aprsIsConn.updateFilter(camera.visibleBounds);
      }
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
        final visible = _visibleStations();
        _markers = visible.map(_buildMarker).toList();
        _trackPolylines = _buildTrackPolylines(visible);
      });
    });
  }

  /// Returns the subset of stations that pass the current display-age filter,
  /// sorted ascending by [Station.lastHeard] so newest render on top.
  ///
  /// This is a **view filter only** — no station data is deleted.
  List<Station> _visibleStations() {
    final maxAge = _service.stationMaxAgeMinutes;
    final cutoff = maxAge != null
        ? DateTime.now().toUtc().subtract(Duration(minutes: maxAge))
        : null;
    return _service.currentStations.values
        .where((s) => cutoff == null || !s.lastHeard.toUtc().isBefore(cutoff))
        .toList()
      ..sort((a, b) => a.lastHeard.compareTo(b.lastHeard));
  }

  List<Polyline> _buildTrackPolylines(List<Station> visible) {
    final secondary = Theme.of(
      context,
    ).colorScheme.secondary.withValues(alpha: 0.6);
    final maxAge = _service.stationMaxAgeMinutes;
    final cutoff = maxAge != null
        ? DateTime.now().toUtc().subtract(Duration(minutes: maxAge))
        : null;
    return visible
        .where((s) => s.positionHistory.isNotEmpty)
        .map((s) {
          final pts = cutoff == null
              ? s.positionHistory
              : s.positionHistory
                    .where((p) => !p.timestamp.toUtc().isBefore(cutoff))
                    .toList();
          if (pts.isEmpty) return null;
          return Polyline(
            points: [...pts.map((p) => p.position), LatLng(s.lat, s.lon)],
            color: secondary,
            strokeWidth: 2.0,
          );
        })
        .whereType<Polyline>()
        .toList();
  }

  /// Returns a short label string when [maxAge] is non-default (not 60 min),
  /// or null when no chip should be shown.
  String? _activeFilterLabel(int? maxAge) {
    if (maxAge == 60) return null; // default — no chip
    if (maxAge == null) return 'No limit';
    if (maxAge < 60) return '$maxAge min';
    final hours = maxAge ~/ 60;
    return '${hours}h';
  }

  void _openFilterPanel() {
    final stationService = context.read<StationService>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => MeridianBottomSheet(
        child: MapFilterPanel(
          currentMaxAgeMinutes: stationService.stationMaxAgeMinutes,
          showTracks: _showTracks,
          onMaxAgeChanged: (v) => stationService.setStationMaxAgeMinutes(v),
          onShowTracksChanged: (v) => setState(() => _showTracks = v),
        ),
      ),
    );
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
    final themeController = context.watch<ThemeController>();
    final brightness = switch (themeController.themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => MediaQuery.of(context).platformBrightness,
    };

    // Show an active-filter chip when the time window is non-default (≠60 min).
    final maxAge = context.watch<StationService>().stationMaxAgeMinutes;
    final activeFilterLabel = _activeFilterLabel(maxAge);

    return ResponsiveLayout(
      service: _service,
      mapController: _mapController,
      markers: _markers,
      tileUrl: _tileProvider.tileUrl(brightness),
      meridianTileProvider: _tileProvider,
      onNavigateToSettings: _navigateToSettings,
      initialCenter: LatLng(widget.initialLat, widget.initialLon),
      initialZoom: widget.initialZoom,
      northUpLocked: _northUpLocked,
      onToggleNorthUp: _toggleNorthUp,
      showTracks: _showTracks,
      trackPolylines: _trackPolylines,
      onOpenFilterPanel: _openFilterPanel,
      activeFilterLabel: activeFilterLabel,
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
