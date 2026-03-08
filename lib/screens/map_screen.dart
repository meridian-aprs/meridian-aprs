import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/packet/station.dart';
import '../core/transport/aprs_is_transport.dart';
import '../services/station_service.dart';
import '../ui/widgets/station_info_sheet.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late final StationService _service;
  final _mapController = MapController();
  List<Marker> _markers = [];
  Timer? _filterDebounce;
  Timer? _markerDebounce;

  @override
  void initState() {
    super.initState();
    final transport = AprsIsTransport(
      loginLine: 'user NOCALL pass -1 vers meridian-aprs 0.1\r\n',
      filterLine: '#filter r/39.0/-77.0/100\r\n',
    );
    _service = StationService(transport);
    _service.stationUpdates.listen(_onStationsUpdated);
    _service.start();
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
      debugPrint('Filter update: ${center.latitude}, ${center.longitude}');
      _service.updateFilter(center.latitude, center.longitude);
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
        return Colors.red;
      // Weather
      case '_':
        return Colors.blue;
      default:
        return Colors.blueGrey;
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
        child: Icon(
          symbolIcon(s.symbolCode),
          color: _markerColor(s.symbolCode),
          size: 36,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meridian APRS')),
      body: FlutterMap(
        mapController: _mapController,
        options: const MapOptions(
          initialCenter: LatLng(39.0, -77.0),
          initialZoom: 9,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.meridianaprs.app',
          ),
          MarkerLayer(markers: _markers),
        ],
      ),
    );
  }
}
