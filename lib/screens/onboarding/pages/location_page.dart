import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../screens/location_picker_screen.dart';
import '../../../services/station_settings_service.dart';
import '../../../ui/utils/platform_route.dart';

/// Onboarding step 4 — GPS permission and location setup.
class LocationPage extends StatefulWidget {
  const LocationPage({super.key, required this.onNext, required this.onBack});

  /// Advance to the next onboarding step.
  final VoidCallback onNext;

  /// Go back to the previous step.
  final VoidCallback onBack;

  @override
  State<LocationPage> createState() => _LocationPageState();
}

enum _LocationState { initial, resolving, resolved, denied, unsupported }

class _LocationPageState extends State<LocationPage> {
  _LocationState _state = _LocationState.initial;
  double? _resolvedLat;
  double? _resolvedLon;

  Future<void> _onEnableGps() async {
    final settings = context.read<StationSettingsService>();
    setState(() => _state = _LocationState.resolving);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _state = _LocationState.denied);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _state = _LocationState.denied);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );

      if (!mounted) return;
      await settings.setLocationSource(LocationSource.gps);

      setState(() {
        _state = _LocationState.resolved;
        _resolvedLat = position.latitude;
        _resolvedLon = position.longitude;
      });
    } on MissingPluginException {
      if (mounted) setState(() => _state = _LocationState.unsupported);
    } catch (_) {
      if (mounted) setState(() => _state = _LocationState.denied);
    }
  }

  Future<void> _openLocationPicker() async {
    LatLng? initial;
    final settings = context.read<StationSettingsService>();
    if (settings.hasManualPosition) {
      initial = LatLng(settings.manualLat!, settings.manualLon!);
    }

    final result = await Navigator.push<LatLng>(
      context,
      buildPlatformRoute((_) => LocationPickerScreen(initial: initial)),
    );

    if (result != null && mounted) {
      await settings.setManualPosition(result.latitude, result.longitude);
      await settings.setLocationSource(LocationSource.manual);
      if (mounted) {
        setState(() {
          _state = _LocationState.resolved;
          _resolvedLat = result.latitude;
          _resolvedLon = result.longitude;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Set your location',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Meridian uses your location to centre the map and for '
              'beaconing. You can also set it manually or skip for now.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 40),
            _buildBody(theme, colorScheme),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: widget.onNext,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapPreview(ThemeData theme, ColorScheme colorScheme) {
    final isDark = theme.brightness == Brightness.dark;
    final tileUrl = isDark
        ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    final pin = LatLng(_resolvedLat!, _resolvedLon!);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 200,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: pin,
            initialZoom: 13,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: tileUrl,
              userAgentPackageName: 'com.meridianaprs.app',
              subdomains: isDark ? const ['a', 'b', 'c', 'd'] : const [],
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: pin,
                  width: 40,
                  height: 40,
                  alignment: Alignment.topCenter,
                  child: Icon(
                    Symbols.location_on,
                    size: 40,
                    color: colorScheme.error,
                    shadows: const [
                      Shadow(blurRadius: 4, color: Colors.black38),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme colorScheme) {
    switch (_state) {
      case _LocationState.initial:
        return Center(
          child: Column(
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 64,
                color: colorScheme.primary,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: _onEnableGps,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Enable GPS'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _openLocationPicker,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Pick on map'),
                ),
              ),
            ],
          ),
        );

      case _LocationState.resolving:
        return const Center(child: CircularProgressIndicator.adaptive());

      case _LocationState.resolved:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMapPreview(theme, colorScheme),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  color: colorScheme.primary,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Location set. You can change this later in Settings.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );

      case _LocationState.denied:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_off, color: colorScheme.error),
                const SizedBox(width: 12),
                Text(
                  'GPS access denied',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'You can enable location access in System Settings, or set '
              'your position manually.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _openLocationPicker,
              icon: const Icon(Icons.map_outlined),
              label: const Text('Pick on map'),
            ),
          ],
        );

      case _LocationState.unsupported:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_off, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Text(
                  'GPS not available on this platform',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Set your position manually for beaconing.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _openLocationPicker,
              icon: const Icon(Icons.map_outlined),
              label: const Text('Pick on map'),
            ),
          ],
        );
    }
  }
}
