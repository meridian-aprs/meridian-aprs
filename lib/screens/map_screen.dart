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
  // Periodic tick so the display-age filter slides in real time even when no
  // new packets arrive. Fires every 60 s to fade/restore stations at the
  // current time-window boundary without deleting any underlying data.
  Timer? _slidingWindowTick;
  StreamSubscription<TxEvent>? _txEventSub;
  bool _northUpLocked = true;
  bool _showTracks = false;
  int _visibleStationCount = 0;
  int _totalStationCount = 0;

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
      (_) => _onStationsUpdated(_service.currentStations),
    );
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
    _slidingWindowTick?.cancel();
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
      // Recluster at new zoom level so marker density stays appropriate.
      _onStationsUpdated(_service.currentStations);
    });
  }

  void _onStationsUpdated(Map<String, Station> stations) {
    _markerDebounce?.cancel();
    _markerDebounce = Timer(const Duration(milliseconds: 300), () {
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
      });
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
          currentHiddenTypes: stationService.hiddenTypes,
          onHiddenTypesChanged: (types) => stationService.setHiddenTypes(types),
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

  // ---------------------------------------------------------------------------
  // Clustering
  // ---------------------------------------------------------------------------

  /// Geographic clustering radius in degrees, equivalent to ~28 screen pixels
  /// at the current zoom level — roughly the overlap threshold for 44 px tap
  /// targets. Stations cluster only when they are nearly on top of each other.
  ///
  /// Derived from the tile-pixel relationship: 1° ≈ 0.711 × 2^zoom pixels,
  /// so N px ≈ (N / 0.711) / 2^zoom degrees.
  ///
  /// Example values:
  ///   zoom 10 → ~0.039° (~4.3 km)
  ///   zoom 12 → ~0.010° (~1.1 km)
  ///   zoom 14 → ~0.002° (~270 m)
  double get _clusterRadiusDegrees {
    double zoom;
    try {
      zoom = _mapController.camera.zoom;
    } catch (_) {
      zoom = 9.0;
    }
    return 40.0 / math.pow(2, zoom);
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
    child: GestureDetector(
      onTapDown: (d) => _showClusterPopover(d.globalPosition, g.stations),
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
          builder: (_) => StationInfoSheet(station: selected),
        );
      }
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
      visibleStationCount: _visibleStationCount,
      totalStationCount: _totalStationCount,
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
      painter: _ClusterRingPainter(typeCounts: typeCounts, total: count),
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
