/// Interactive location picker for manual beacon position.
///
/// Shows a map with a draggable pin and an address search bar that uses the
/// Nominatim geocoding API (OpenStreetMap). Returns a [LatLng] when the user
/// confirms, or null if they cancel.
///
/// Usage:
/// ```dart
/// final result = await Navigator.push<LatLng>(
///   context,
///   MaterialPageRoute(builder: (_) => const LocationPickerScreen()),
/// );
/// if (result != null) { /* save position */ }
/// ```
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';

/// A single result returned by the Nominatim geocoder.
class _GeoResult {
  const _GeoResult({required this.displayName, required this.position});

  final String displayName;
  final LatLng position;
}

class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key, this.initial});

  /// Pre-seed the pin at this position (e.g. the previously stored position).
  final LatLng? initial;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  late final MapController _mapController;
  late final TextEditingController _searchCtrl;

  LatLng? _pin;
  bool _searching = false;
  String? _searchError;
  List<_GeoResult> _suggestions = [];

  static const _defaultCenter = LatLng(39.0, -77.0);
  static const _defaultZoom = 5.0;
  static const _pinZoom = 14.0;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _searchCtrl = TextEditingController();
    _pin = widget.initial;
  }

  @override
  void dispose() {
    _mapController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Geocoding (Nominatim)
  // ---------------------------------------------------------------------------

  Future<void> _search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;

    setState(() {
      _searching = true;
      _searchError = null;
      _suggestions = [];
    });

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': q,
        'format': 'json',
        'limit': '5',
        'addressdetails': '0',
      });
      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'MeridianAPRS/0.5 (https://meridianaprs.app)',
          'Accept-Language': 'en',
        },
      );

      if (response.statusCode != 200) {
        setState(() => _searchError = 'Search failed (${response.statusCode})');
        return;
      }

      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      final results = data.map((e) {
        final map = e as Map<String, dynamic>;
        return _GeoResult(
          displayName: map['display_name'] as String,
          position: LatLng(
            double.parse(map['lat'] as String),
            double.parse(map['lon'] as String),
          ),
        );
      }).toList();

      if (results.isEmpty) {
        setState(() => _searchError = 'No results for "$q"');
        return;
      }

      if (results.length == 1) {
        _selectResult(results.first);
      } else {
        setState(() => _suggestions = results);
      }
    } catch (_) {
      setState(
        () => _searchError =
            'Could not reach geocoding service — tap the map to place a pin instead',
      );
    } finally {
      setState(() => _searching = false);
    }
  }

  void _selectResult(_GeoResult result) {
    setState(() {
      _pin = result.position;
      _suggestions = [];
      _searchCtrl.text = result.displayName;
    });
    _mapController.move(result.position, _pinZoom);
    FocusScope.of(context).unfocus();
  }

  void _onMapTap(TapPosition _, LatLng pos) {
    setState(() {
      _pin = pos;
      _suggestions = [];
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tileUrl = isDark
        ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick Location'),
        actions: [
          if (_pin != null)
            FilledButton.icon(
              icon: const Icon(Symbols.check),
              label: const Text('Use'),
              onPressed: () => Navigator.of(context).pop(_pin),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // ── Search bar ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SearchBar(
              controller: _searchCtrl,
              hintText: 'Search address (requires internet)…',
              leading: _searching
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : const Icon(Symbols.search),
              trailing: [
                if (_searchCtrl.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Symbols.close),
                    tooltip: 'Clear',
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() {
                        _suggestions = [];
                        _searchError = null;
                      });
                    },
                  ),
              ],
              onSubmitted: _search,
              onChanged: (_) => setState(() {}),
            ),
          ),

          // ── Error notice ──
          if (_searchError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(
                children: [
                  Icon(Symbols.info, size: 16, color: theme.colorScheme.error),
                  const SizedBox(width: 6),
                  Text(
                    _searchError!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ),
            ),

          // ── Suggestion list (overlaps map) ──
          if (_suggestions.isNotEmpty)
            Card(
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _suggestions.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final r = _suggestions[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Symbols.location_on),
                    title: Text(
                      r.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _selectResult(r),
                  );
                },
              ),
            ),

          // ── Hint when no pin placed yet ──
          if (_pin == null && _suggestions.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Symbols.touch_app,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Search for a place (requires internet) or tap the map to place a pin',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 6),

          // ── Map ──
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _pin ?? _defaultCenter,
                    initialZoom: _pin != null ? _pinZoom : _defaultZoom,
                    onTap: _onMapTap,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: tileUrl,
                      userAgentPackageName: 'com.meridianaprs.app',
                      subdomains: isDark
                          ? const ['a', 'b', 'c', 'd']
                          : const [],
                    ),
                    if (_pin != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _pin!,
                            width: 40,
                            height: 40,
                            alignment: Alignment.topCenter,
                            child: Icon(
                              Symbols.location_on,
                              size: 40,
                              color: theme.colorScheme.error,
                              shadows: const [
                                Shadow(blurRadius: 4, color: Colors.black38),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),

                // ── Coordinate readout ──
                if (_pin != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 12,
                    child: Center(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Text(
                            '${_pin!.latitude.toStringAsFixed(6)}°, '
                            '${_pin!.longitude.toStringAsFixed(6)}°',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
