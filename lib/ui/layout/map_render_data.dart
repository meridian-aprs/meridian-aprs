import 'package:flutter_map/flutter_map.dart';

import '../../core/packet/station.dart';

/// Immutable snapshot of the per-packet-changing map render state.
///
/// MapScreen holds this in a `ValueNotifier` and threads it down to
/// [MeridianMap], which consumes it through `ValueListenableBuilder`s at the
/// marker / polyline / overlay-chip leaves. Station and packet updates then
/// rebuild only those leaves — not the surrounding scaffold chrome (AppBar,
/// FABs, filter chips, navigation bar). See Issue #51 (v0.19, Performance).
///
/// Intentionally has **no value `==`**: each `_rebuildMarkers` produces a fresh
/// instance and the notifier fires by identity. A deep list comparison would be
/// costly and could suppress legitimate updates — and is unnecessary because the
/// 300 ms marker debounce already throttles the update rate.
class MapRenderData {
  const MapRenderData({
    this.markers = const <Marker>[],
    this.trackPolylines = const <Polyline>[],
    this.visibleStationCount = 0,
    this.totalStationCount = 0,
    this.nearestWxStation,
  });

  /// Pre-built station / cluster markers at the current camera zoom.
  final List<Marker> markers;

  /// Pre-built movement-track polylines (only rendered when tracks are on).
  final List<Polyline> trackPolylines;

  /// Stations passing the current display filter.
  final int visibleStationCount;

  /// Total known stations (unfiltered).
  final int totalStationCount;

  /// Nearest weather station to the map center, if any.
  final Station? nearestWxStation;
}
