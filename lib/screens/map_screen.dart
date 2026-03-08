import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/packet/station.dart';
import '../core/transport/aprs_is_transport.dart';
import '../services/station_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late final StationService _service;
  List<Marker> _markers = [];

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
  }

  @override
  void dispose() {
    _service.stop();
    super.dispose();
  }

  void _onStationsUpdated(Map<String, Station> stations) {
    setState(() {
      _markers = stations.values.map(_buildMarker).toList();
    });
  }

  Marker _buildMarker(Station s) => Marker(
    point: LatLng(s.lat, s.lon),
    child: Tooltip(
      message: s.callsign,
      child: const Icon(Icons.location_on, color: Colors.red, size: 24),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meridian APRS')),
      body: FlutterMap(
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
