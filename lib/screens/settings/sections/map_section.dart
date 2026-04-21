import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../services/station_service.dart';
import '../../../ui/utils/distance_formatter.dart';
import '../widgets/section_header.dart';

class MapSection extends StatelessWidget {
  const MapSection({super.key});

  static const _options = <({String label, int? value})>[
    (label: '15 min', value: 15),
    (label: '30 min', value: 30),
    (label: '1 hour', value: 60),
    (label: '2 hours', value: 120),
    (label: '6 hours', value: 360),
    (label: '12 hours', value: 720),
    (label: 'No limit', value: null),
  ];

  // Radius option values are always stored in km internally.
  static const _radiusOptionValues = [10, 25, 50, 100];

  static const _wxAgeOptions = <({String label, int value})>[
    (label: '15 min', value: 15),
    (label: '30 min', value: 30),
    (label: '1 hr', value: 60),
    (label: '2 hr', value: 120),
  ];

  static String _labelFor(int? value) => _options
      .firstWhere((o) => o.value == value, orElse: () => _options[2])
      .label;

  static String _radiusLabelFor(int km, {required bool imperial}) =>
      formatRadiusKm(
        _radiusOptionValues.contains(km) ? km : 50,
        imperial: imperial,
      );

  static String _wxAgeLabelFor(int value) => _wxAgeOptions
      .firstWhere((o) => o.value == value, orElse: () => _wxAgeOptions[2])
      .label;

  @override
  Widget build(BuildContext context) {
    final stations = context.watch<StationService>();
    final current = stations.stationMaxAgeMinutes;

    if (!kIsWeb && Platform.isIOS) {
      return _buildIos(context, stations, current);
    }
    return _buildMaterial(context, stations, current);
  }

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

  Widget _buildMaterial(
    BuildContext context,
    StationService stations,
    int? current,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Map'),
        SwitchListTile.adaptive(
          title: const Text('Distance units'),
          subtitle: const Text('Use miles and feet instead of km and metres'),
          secondary: const Icon(Symbols.straighten),
          value: stations.useImperialUnits,
          onChanged: (v) => stations.setUseImperialUnits(v),
        ),
        ListTile(
          title: const Text('Station timeout'),
          subtitle: const Text('Hide stations not heard within this window.'),
          trailing: DropdownButton<int?>(
            value: current,
            underline: const SizedBox.shrink(),
            items: _options
                .map(
                  (o) => DropdownMenuItem<int?>(
                    value: o.value,
                    child: Text(o.label),
                  ),
                )
                .toList(),
            onChanged: (v) => stations.setStationMaxAgeMinutes(v),
          ),
        ),
        SwitchListTile.adaptive(
          title: const Text('Weather overlay'),
          subtitle: const Text('Show conditions from nearest WX station'),
          value: stations.showWeatherOverlay,
          onChanged: (v) => stations.setShowWeatherOverlay(v),
        ),
        if (stations.showWeatherOverlay) ...[
          ListTile(
            contentPadding: const EdgeInsets.only(left: 32, right: 16),
            title: const Text('Search radius'),
            subtitle: const Text('Maximum distance to nearest WX station'),
            trailing: Text(
              _radiusLabelFor(
                stations.weatherOverlayRadiusKm,
                imperial: stations.useImperialUnits,
              ),
            ),
            onTap: () => _showRadiusDialog(
              context,
              stations,
              imperial: stations.useImperialUnits,
            ),
          ),
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.only(left: 32, right: 16),
            title: const Text('Show in °C'),
            subtitle: const Text('Display temperature in Celsius'),
            value: stations.weatherOverlayUseCelsius,
            onChanged: (v) => stations.setWeatherOverlayUseCelsius(v),
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
      ],
    );
  }

  Widget _buildIos(
    BuildContext context,
    StationService stations,
    int? current,
  ) {
    final selectedIndex = _options
        .indexWhere((o) => o.value == current)
        .clamp(0, _options.length - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Map'),
        SwitchListTile.adaptive(
          title: const Text('Distance units'),
          subtitle: const Text('Use miles and feet instead of km and metres'),
          secondary: const Icon(Symbols.straighten),
          value: stations.useImperialUnits,
          onChanged: (v) => stations.setUseImperialUnits(v),
        ),
        ListTile(
          title: const Text('Station timeout'),
          subtitle: const Text('Hide stations not heard within this window.'),
          trailing: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => showCupertinoModalPopup<void>(
              context: context,
              builder: (_) => SizedBox(
                height: 216,
                child: CupertinoPicker(
                  backgroundColor: CupertinoTheme.of(
                    context,
                  ).scaffoldBackgroundColor,
                  scrollController: FixedExtentScrollController(
                    initialItem: selectedIndex,
                  ),
                  itemExtent: 36,
                  onSelectedItemChanged: (i) =>
                      stations.setStationMaxAgeMinutes(_options[i].value),
                  children: _options.map((o) => Text(o.label)).toList(),
                ),
              ),
            ),
            child: Text(_labelFor(current)),
          ),
        ),
        SwitchListTile.adaptive(
          title: const Text('Weather overlay'),
          subtitle: const Text('Show conditions from nearest WX station'),
          value: stations.showWeatherOverlay,
          onChanged: (v) => stations.setShowWeatherOverlay(v),
        ),
        if (stations.showWeatherOverlay) ...[
          ListTile(
            contentPadding: const EdgeInsets.only(left: 32, right: 16),
            title: const Text('Search radius'),
            subtitle: const Text('Maximum distance to nearest WX station'),
            trailing: Text(
              _radiusLabelFor(
                stations.weatherOverlayRadiusKm,
                imperial: stations.useImperialUnits,
              ),
            ),
            onTap: () => _showRadiusDialog(
              context,
              stations,
              imperial: stations.useImperialUnits,
            ),
          ),
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.only(left: 32, right: 16),
            title: const Text('Show in °C'),
            subtitle: const Text('Display temperature in Celsius'),
            value: stations.weatherOverlayUseCelsius,
            onChanged: (v) => stations.setWeatherOverlayUseCelsius(v),
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
      ],
    );
  }
}
