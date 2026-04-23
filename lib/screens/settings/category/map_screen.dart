import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../services/station_service.dart';
import '../../../ui/utils/distance_formatter.dart';
import '../advanced_mode_controller.dart';
import '../widgets/section_header.dart';

enum _DistanceUnit { metric, imperial }

enum _TempUnit { fahrenheit, celsius }

class MapSettingsContent extends StatelessWidget {
  const MapSettingsContent({super.key});

  static const _radiusOptionValues = [10, 25, 50, 100];

  static const _wxAgeOptions = <({String label, int value})>[
    (label: '15 min', value: 15),
    (label: '30 min', value: 30),
    (label: '1 hr', value: 60),
    (label: '2 hr', value: 120),
  ];

  static String _radiusLabelFor(int km, {required bool imperial}) =>
      formatRadiusKm(
        _radiusOptionValues.contains(km) ? km : 50,
        imperial: imperial,
      );

  static String _wxAgeLabelFor(int value) => _wxAgeOptions
      .firstWhere((o) => o.value == value, orElse: () => _wxAgeOptions[2])
      .label;

  void _showRadiusDialog(
    BuildContext context,
    StationService stations, {
    required bool imperial,
  }) {
    showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('WX search radius'),
        children: _radiusOptionValues
            .map(
              (km) => SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(km),
                child: Text(
                  formatRadiusKm(km, imperial: imperial),
                  style: km == stations.weatherOverlayRadiusKm
                      ? TextStyle(
                          color: Theme.of(ctx).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        )
                      : null,
                ),
              ),
            )
            .toList(),
      ),
    ).then((v) {
      if (v != null) stations.setWeatherOverlayRadiusKm(v);
    });
  }

  void _showWxAgeDialog(BuildContext context, StationService stations) {
    showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('WX data max age'),
        children: _wxAgeOptions
            .map(
              (o) => SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(o.value),
                child: Text(
                  o.label,
                  style: o.value == stations.weatherOverlayMaxAgeMinutes
                      ? TextStyle(
                          color: Theme.of(ctx).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        )
                      : null,
                ),
              ),
            )
            .toList(),
      ),
    ).then((v) {
      if (v != null) stations.setWeatherOverlayMaxAgeMinutes(v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final stations = context.watch<StationService>();
    final advanced = context.watch<AdvancedModeController>();
    final imperial = stations.useImperialUnits;
    final isIos = !kIsWeb && Platform.isIOS;

    final distanceUnit = imperial
        ? _DistanceUnit.imperial
        : _DistanceUnit.metric;
    final tempUnit = stations.weatherOverlayUseCelsius
        ? _TempUnit.celsius
        : _TempUnit.fahrenheit;

    return ListView(
      children: [
        const SectionHeader('Map'),

        // Distance units — segmented control
        ListTile(
          title: const Text('Distance units'),
          leading: const Icon(Symbols.straighten),
          trailing: isIos
              ? _CupertinoDistanceSegment(
                  value: distanceUnit,
                  onChanged: (v) =>
                      stations.setUseImperialUnits(v == _DistanceUnit.imperial),
                )
              : SegmentedButton<_DistanceUnit>(
                  segments: const [
                    ButtonSegment(
                      value: _DistanceUnit.metric,
                      label: Text('Metric'),
                    ),
                    ButtonSegment(
                      value: _DistanceUnit.imperial,
                      label: Text('Imperial'),
                    ),
                  ],
                  selected: {distanceUnit},
                  onSelectionChanged: (s) {
                    if (s.isNotEmpty) {
                      stations.setUseImperialUnits(
                        s.first == _DistanceUnit.imperial,
                      );
                    }
                  },
                ),
        ),

        // Weather overlay toggle (always visible)
        SwitchListTile.adaptive(
          title: const Text('Weather overlay'),
          subtitle: const Text('Show conditions from nearest WX station'),
          value: stations.showWeatherOverlay,
          onChanged: (v) => stations.setShowWeatherOverlay(v),
        ),

        // Advanced weather overlay sub-controls
        if (stations.showWeatherOverlay && advanced.isEnabled) ...[
          ListTile(
            contentPadding: const EdgeInsets.only(left: 32, right: 16),
            title: const Text('Search radius'),
            subtitle: const Text('Maximum distance to nearest WX station'),
            trailing: Text(
              _radiusLabelFor(
                stations.weatherOverlayRadiusKm,
                imperial: imperial,
              ),
            ),
            onTap: () =>
                _showRadiusDialog(context, stations, imperial: imperial),
          ),
          ListTile(
            contentPadding: const EdgeInsets.only(left: 32, right: 16),
            title: const Text('Temperature units'),
            trailing: isIos
                ? _CupertinoTempSegment(
                    value: tempUnit,
                    onChanged: (v) => stations.setWeatherOverlayUseCelsius(
                      v == _TempUnit.celsius,
                    ),
                  )
                : SegmentedButton<_TempUnit>(
                    segments: const [
                      ButtonSegment(
                        value: _TempUnit.fahrenheit,
                        label: Text('°F'),
                      ),
                      ButtonSegment(
                        value: _TempUnit.celsius,
                        label: Text('°C'),
                      ),
                    ],
                    selected: {tempUnit},
                    onSelectionChanged: (s) {
                      if (s.isNotEmpty) {
                        stations.setWeatherOverlayUseCelsius(
                          s.first == _TempUnit.celsius,
                        );
                      }
                    },
                  ),
          ),
          ListTile(
            contentPadding: const EdgeInsets.only(left: 32, right: 16),
            title: const Text('Data max age'),
            subtitle: const Text('Ignore WX reports older than this'),
            trailing: Text(
              _wxAgeLabelFor(stations.weatherOverlayMaxAgeMinutes),
            ),
            onTap: () => _showWxAgeDialog(context, stations),
          ),
        ],

        const SizedBox(height: 16),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// iOS Cupertino segmented controls
// ---------------------------------------------------------------------------

class _CupertinoDistanceSegment extends StatelessWidget {
  const _CupertinoDistanceSegment({
    required this.value,
    required this.onChanged,
  });

  final _DistanceUnit value;
  final ValueChanged<_DistanceUnit> onChanged;

  @override
  Widget build(BuildContext context) {
    return CupertinoSlidingSegmentedControl<_DistanceUnit>(
      groupValue: value,
      onValueChanged: (v) {
        if (v != null) onChanged(v);
      },
      children: const {
        _DistanceUnit.metric: Text('Metric'),
        _DistanceUnit.imperial: Text('Imperial'),
      },
    );
  }
}

class _CupertinoTempSegment extends StatelessWidget {
  const _CupertinoTempSegment({required this.value, required this.onChanged});

  final _TempUnit value;
  final ValueChanged<_TempUnit> onChanged;

  @override
  Widget build(BuildContext context) {
    return CupertinoSlidingSegmentedControl<_TempUnit>(
      groupValue: value,
      onValueChanged: (v) {
        if (v != null) onChanged(v);
      },
      children: const {
        _TempUnit.fahrenheit: Text('°F'),
        _TempUnit.celsius: Text('°C'),
      },
    );
  }
}
