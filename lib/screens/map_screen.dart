import 'dart:async';
import 'dart:math' as math;

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
import '../ui/utils/distance_formatter.dart';
import '../ui/utils/maidenhead.dart';
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
  Timer? _reclusterDebounce;
  // Periodic tick so the display-age filter slides in real time even when no
  // new packets arrive. Fires every 60 s to fade/restore stations at the
  // current time-window boundary without deleting any underlying data.
  Timer? _slidingWindowTick;
  StreamSubscription<TxEvent>? _txEventSub;
  bool _northUpLocked = true;
  int _visibleStationCount = 0;
  int _totalStationCount = 0;
  Station? _nearestWxStation;
  LatLng? _pinLocation;

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
    // Sliding-window tick: re-evaluate visible stations every 60 s so stations
    // fade off (or pop back) as real time crosses the filter boundary.
    _slidingWindowTick = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _rebuildMarkers(),
    );
    _txEventSub = context.read<TxService>().events.listen(_onTxEvent);

    // APRS-IS filter update and prefs persistence: wait until the map fully
    // settles (momentum animation ends) before sending a new server filter.
    _mapController.mapEventStream
        .where((e) => e is MapEventMoveEnd)
        .cast<MapEventMoveEnd>()
        .listen(_onMapMoveEnd);

    // Recluster on any camera change (pan, pinch-zoom, scroll wheel).
    // MapEventMove fires every frame during a gesture, so we debounce it at
    // 120 ms — snappy enough to feel responsive, cheap enough not to thrash.
    _mapController.mapEventStream.where((e) => e is MapEventMove).listen((_) {
      _reclusterDebounce?.cancel();
      _reclusterDebounce = Timer(
        const Duration(milliseconds: 120),
        _rebuildMarkers,
      );
    });
  }

  @override
  void dispose() {
    _filterDebounce?.cancel();
    _markerDebounce?.cancel();
    _reclusterDebounce?.cancel();
    _slidingWindowTick?.cancel();
    _txEventSub?.cancel();
    _service.removeListener(_onServiceSettingChanged);
    _tileProvider.dispose();
    super.dispose();
  }

  /// Called when [StationService] notifies — e.g. when [stationMaxAgeMinutes]
  /// changes. Rebuilds markers so the display filter takes effect immediately.
  void _onServiceSettingChanged() {
    _rebuildMarkers();
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
    // Debounce data-arrival rebuilds — in a busy APRS-IS feed, packets arrive
    // faster than the render rate. We coalesce rapid updates into one rebuild.
    _markerDebounce?.cancel();
    _markerDebounce = Timer(const Duration(milliseconds: 300), _rebuildMarkers);
  }

  /// Immediately rebuilds cluster markers at the current camera zoom level.
  ///
  /// Called directly from zoom-change paths (_onMapMoveEnd, _zoomToCluster)
  /// so that cluster recalculation is not blocked by a pending data-arrival
  /// debounce that may never fire in a busy packet stream.
  void _rebuildMarkers() {
    if (!mounted) return;
    setState(() {
      final visible = _visibleStations();
      final clusters = _clusterStations(visible);
      _markers = clusters
          .map(
            (g) => g.stations.length == 1
                ? _buildMarker(g.stations.first)
                : _buildClusterMarker(g),
          )
          .toList();
      _trackPolylines = _buildTrackPolylines(visible);
      _visibleStationCount = visible.length;
      _totalStationCount = _service.currentStations.length;
      _nearestWxStation = _nearestWeatherStation();
    });
  }

  /// Returns the subset of stations that pass the current display filters,
  /// sorted ascending by [Station.lastHeard] so newest render on top.
  ///
  /// This is a **view filter only** — no station data is deleted.
  List<Station> _visibleStations() {
    final maxAge = _service.stationMaxAgeMinutes;
    final cutoff = maxAge != null
        ? DateTime.now().toUtc().subtract(Duration(minutes: maxAge))
        : null;
    final hidden = _service.hiddenTypes;
    return _service.currentStations.values
        .where((s) => cutoff == null || !s.lastHeard.toUtc().isBefore(cutoff))
        .where((s) => !hidden.contains(s.type))
        .toList()
      ..sort((a, b) => a.lastHeard.compareTo(b.lastHeard));
  }

  List<Polyline> _buildTrackPolylines(List<Station> visible) {
    const trackColor = Color(
      0xFFE040FB,
    ); // magenta (Material purple-accent-200)
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
            color: trackColor,
            strokeWidth: 3.0,
          );
        })
        .whereType<Polyline>()
        .toList();
  }

  /// Returns the nearest weather [Station] within the configured radius of the
  /// current map center, or null if the overlay is disabled or no WX station
  /// is in range.
  Station? _nearestWeatherStation() {
    if (!_service.showWeatherOverlay) return null;
    LatLng center;
    try {
      center = _mapController.camera.center;
    } catch (_) {
      center = LatLng(widget.initialLat, widget.initialLon);
    }
    final cutoff = DateTime.now().toUtc().subtract(
      Duration(minutes: _service.weatherOverlayMaxAgeMinutes),
    );
    const dist = Distance();
    Station? nearest;
    double nearestKm = _service.weatherOverlayRadiusKm.toDouble();
    for (final s in _service.currentStations.values) {
      if (s.type != StationType.weather) continue;
      if (s.lastHeard.toUtc().isBefore(cutoff)) continue;
      final km = dist.as(LengthUnit.Kilometer, center, LatLng(s.lat, s.lon));
      if (km < nearestKm) {
        nearestKm = km;
        nearest = s;
      }
    }
    return nearest;
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
          showTracks: _service.showTracks,
          onMaxAgeChanged: (v) => stationService.setStationMaxAgeMinutes(v),
          onShowTracksChanged: (v) => _service.setShowTracks(v),
          visibleStationCount: _visibleStationCount,
          totalStationCount: _totalStationCount,
          currentHiddenTypes: stationService.hiddenTypes,
          onHiddenTypesChanged: (types) => stationService.setHiddenTypes(types),
        ),
      ),
    );
  }

  /// Opacity for a station marker: full for most of the filter window, fading
  /// to 30 % only in the last 10 % of the configured max-age window.
  double _markerOpacity(Station s) {
    final maxAge = _service.stationMaxAgeMinutes;
    if (maxAge == null) return 1.0;
    final ageMins =
        DateTime.now()
            .toUtc()
            .difference(s.lastHeard.toUtc())
            .inSeconds
            .toDouble() /
        60.0;
    final fadeStart = maxAge * 0.9;
    if (ageMins <= fadeStart) return 1.0;
    final t = (ageMins - fadeStart) / (maxAge - fadeStart);
    return (1.0 - t * 0.7).clamp(0.3, 1.0);
  }

  LatLng get _mapCenter {
    try {
      return _mapController.camera.center;
    } catch (_) {
      return LatLng(widget.initialLat, widget.initialLon);
    }
  }

  Marker _buildMarker(Station s) => Marker(
    point: LatLng(s.lat, s.lon),
    width: 44,
    height: 44,
    rotate: true,
    child: GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        builder: (_) =>
            StationInfoSheet(station: s, referencePosition: _mapCenter),
      ),
      child: Tooltip(
        message: s.callsign,
        child: Opacity(
          opacity: _markerOpacity(s),
          child: AprsSymbolWidget(
            symbolTable: s.symbolTable,
            symbolCode: s.symbolCode,
            size: 44,
          ),
        ),
      ),
    ),
  );

  // ---------------------------------------------------------------------------
  // Clustering
  // ---------------------------------------------------------------------------

  /// Geographic clustering radius in degrees, equivalent to ~26 screen pixels
  /// at the current zoom level — the 40 % linear overlap threshold for 44 px
  /// markers. Two markers cluster only when their centres are within
  /// 44 × (1 − 0.4) = 26.4 px of each other.
  ///
  /// Derived from the tile-pixel relationship: 1° ≈ 0.711 × 2^zoom pixels,
  /// so N px ≈ (N / 0.711) / 2^zoom degrees.
  /// 26.4 / 0.711 ≈ 37.1, rounded down to 37.
  ///
  /// Example values:
  ///   zoom 10 → ~0.036° (~4.0 km)
  ///   zoom 12 → ~0.009° (~1.0 km)
  ///   zoom 14 → ~0.002° (~250 m)
  double get _clusterRadiusDegrees {
    double zoom;
    try {
      zoom = _mapController.camera.zoom;
    } catch (_) {
      zoom = 9.0;
    }
    return 37.0 / math.pow(2, zoom);
  }

  /// Greedy O(n²) geographic cluster grouping.
  List<_ClusterGroup> _clusterStations(List<Station> stations) {
    final radius = _clusterRadiusDegrees;
    final groups = <_ClusterGroup>[];
    outer:
    for (final s in stations) {
      for (final g in groups) {
        final c = g.center;
        if ((s.lat - c.latitude).abs() + (s.lon - c.longitude).abs() < radius) {
          g.stations.add(s);
          continue outer;
        }
      }
      groups.add(_ClusterGroup([s]));
    }
    return groups;
  }

  Marker _buildClusterMarker(_ClusterGroup g) => Marker(
    point: g.center,
    width: 48,
    height: 48,
    rotate: true,
    child: GestureDetector(
      onTapUp: (d) => _showClusterPopover(d.globalPosition, g.stations),
      child: _ClusterWidget(typeCounts: g.typeCounts, count: g.stations.length),
    ),
  );

  void _showClusterPopover(Offset globalPos, List<Station> stations) {
    final box = context.findRenderObject()! as RenderBox;
    final local = box.globalToLocal(globalPos);
    showMenu<Station>(
      context: context,
      position: RelativeRect.fromSize(
        Rect.fromLTWH(local.dx, local.dy, 1, 1),
        box.size,
      ),
      items: stations
          .map(
            (s) => PopupMenuItem<Station>(
              value: s,
              child: Row(
                children: [
                  AprsSymbolWidget(
                    symbolTable: s.symbolTable,
                    symbolCode: s.symbolCode,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    s.callsign,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    ).then((selected) {
      if (selected != null && mounted) {
        showModalBottomSheet(
          context: context,
          builder: (_) => StationInfoSheet(
            station: selected,
            referencePosition: _mapCenter,
          ),
        );
      }
    });
  }

  void _dropPin(LatLng location) {
    setState(() => _pinLocation = location);
    showModalBottomSheet<void>(
      context: context,
      builder: (_) =>
          _PinDropSheet(location: location, referencePosition: _mapCenter),
    ).whenComplete(() {
      if (mounted) setState(() => _pinLocation = null);
    });
  }

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

    final stationService = context.watch<StationService>();

    // Show an active-filter chip when the time window is non-default (≠60 min).
    final maxAge = stationService.stationMaxAgeMinutes;
    final activeFilterLabel = _activeFilterLabel(maxAge);

    // Badge the filter FAB when any filter deviates from defaults (60 min,
    // all types visible, tracks on).
    final isFilterActive =
        maxAge != 60 ||
        stationService.hiddenTypes.isNotEmpty ||
        !stationService.showTracks;

    // Pin marker: shown while a long-press pin sheet is open.
    final allMarkers = _pinLocation != null
        ? [
            ..._markers,
            Marker(
              point: _pinLocation!,
              width: 40,
              height: 48,
              child: const Icon(
                Icons.location_pin,
                color: Colors.red,
                size: 40,
              ),
            ),
          ]
        : _markers;

    return ResponsiveLayout(
      service: _service,
      mapController: _mapController,
      markers: allMarkers,
      tileUrl: _tileProvider.tileUrl(brightness),
      meridianTileProvider: _tileProvider,
      onNavigateToSettings: _navigateToSettings,
      initialCenter: LatLng(widget.initialLat, widget.initialLon),
      initialZoom: widget.initialZoom,
      northUpLocked: _northUpLocked,
      onToggleNorthUp: _toggleNorthUp,
      showTracks: _service.showTracks,
      trackPolylines: _trackPolylines,
      onOpenFilterPanel: _openFilterPanel,
      activeFilterLabel: activeFilterLabel,
      visibleStationCount: _visibleStationCount,
      totalStationCount: _totalStationCount,
      nearestWxStation: _nearestWxStation,
      isFilterActive: isFilterActive,
      onMapLongPress: _dropPin,
    );
  }
}

// ---------------------------------------------------------------------------
// Cluster support types
// ---------------------------------------------------------------------------

/// A group of nearby stations that should be rendered as a single cluster
/// marker.
class _ClusterGroup {
  _ClusterGroup(List<Station> initial) : stations = List.of(initial);

  final List<Station> stations;

  LatLng get center {
    final lat =
        stations.map((s) => s.lat).reduce((a, b) => a + b) / stations.length;
    final lon =
        stations.map((s) => s.lon).reduce((a, b) => a + b) / stations.length;
    return LatLng(lat, lon);
  }

  Map<StationType, int> get typeCounts => stations.fold({}, (m, s) {
    m[s.type] = (m[s.type] ?? 0) + 1;
    return m;
  });
}

/// Circular cluster bubble with a colored arc ring indicating type breakdown.
class _ClusterWidget extends StatelessWidget {
  const _ClusterWidget({required this.typeCounts, required this.count});

  final Map<StationType, int> typeCounts;
  final int count;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _ClusterRingPainter(
        typeCounts: typeCounts,
        total: count,
      ),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.surface,
          boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
        ),
        alignment: Alignment.center,
        child: Text(
          '$count',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

/// Draws colored arcs proportional to station type counts as a ring around
/// the cluster bubble.
class _ClusterRingPainter extends CustomPainter {
  const _ClusterRingPainter({required this.typeCounts, required this.total});

  final Map<StationType, int> typeCounts;
  final int total;

  static Color _colorFor(StationType t) => switch (t) {
    StationType.weather => Colors.blue,
    StationType.mobile => Colors.green,
    StationType.fixed => Colors.grey,
    StationType.object => Colors.orange,
    StationType.other => Colors.purple,
  };

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 6.0;
    const gapFraction = 0.015; // fraction of full circle per gap
    final radius = (size.width / 2) - strokeWidth / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);

    final entries = typeCounts.entries.where((e) => e.value > 0).toList();
    if (entries.isEmpty) return;

    // Total gap reduces arc space proportionally.
    final totalGap = gapFraction * entries.length * 2 * math.pi;
    final arcSpace = 2 * math.pi - totalGap;
    final gapAngle = totalGap / entries.length;

    var startAngle = -math.pi / 2; // top of circle
    for (final entry in entries) {
      final sweepAngle = (entry.value / total) * arcSpace;
      final paint = Paint()
        ..color = _colorFor(entry.key)
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
      startAngle += sweepAngle + gapAngle;
    }
  }

  @override
  bool shouldRepaint(_ClusterRingPainter old) =>
      old.typeCounts != typeCounts || old.total != total;
}

/// Bottom sheet shown when the user long-presses on the map to drop a pin.
/// Displays coordinates, Maidenhead grid square, and distance from map center.
class _PinDropSheet extends StatelessWidget {
  const _PinDropSheet({required this.location, this.referencePosition});

  final LatLng location;

  /// The map center at the time the pin was dropped. Used to display distance.
  final LatLng? referencePosition;

  String get _decimalCoordText {
    final lat = location.latitude.toStringAsFixed(5);
    final lon = location.longitude.toStringAsFixed(5);
    return '$lat, $lon';
  }

  /// Formats a decimal degree value as DMS with compass direction.
  static String _dms(double deg, {required bool isLat}) {
    final d = deg.abs().floor();
    final mFull = (deg.abs() - d) * 60;
    final m = mFull.floor();
    final s = ((mFull - m) * 60).round();
    final dir = isLat ? (deg >= 0 ? 'N' : 'S') : (deg >= 0 ? 'E' : 'W');
    return '$d° $m\' $s" $dir';
  }

  String get _dmsText {
    final lat = _dms(location.latitude, isLat: true);
    final lon = _dms(location.longitude, isLat: false);
    return '$lat  $lon';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final imperial = context.watch<StationService>().useImperialUnits;

    final grid = maidenheadLocator(location.latitude, location.longitude);

    double? distKm;
    if (referencePosition != null) {
      distKm = const Distance().as(
        LengthUnit.Kilometer,
        referencePosition!,
        location,
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 32,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title row
            Row(
              children: [
                const Icon(Icons.location_pin, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Dropped Pin',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Decimal coordinates
            _InfoRow(
              icon: Icons.my_location,
              label: _decimalCoordText,
              colorScheme: colorScheme,
              textTheme: theme.textTheme,
              mono: true,
            ),

            const SizedBox(height: 4),

            // DMS coordinates
            _InfoRow(
              icon: Icons.explore,
              label: _dmsText,
              colorScheme: colorScheme,
              textTheme: theme.textTheme,
              mono: true,
            ),

            const SizedBox(height: 4),

            // Maidenhead grid square
            _InfoRow(
              icon: Icons.grid_on,
              label: 'Grid $grid',
              colorScheme: colorScheme,
              textTheme: theme.textTheme,
            ),

            // Distance from map center
            if (distKm != null) ...[
              const SizedBox(height: 4),
              _InfoRow(
                icon: Icons.straighten,
                label: formatDistance(distKm, imperial: imperial),
                colorScheme: colorScheme,
                textTheme: theme.textTheme,
              ),
            ],

            const SizedBox(height: 16),

            // Copy button
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.copy),
                label: const Text('Copy coordinates'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _decimalCoordText));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Coordinates copied'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  Navigator.of(context).pop();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.colorScheme,
    required this.textTheme,
    this.mono = false,
  });

  final IconData icon;
  final String label;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(
          label,
          style:
              (mono
                      ? textTheme.bodyMedium?.copyWith(fontFamily: 'monospace')
                      : textTheme.bodyMedium)
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
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
