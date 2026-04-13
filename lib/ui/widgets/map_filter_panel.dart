import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/packet/station.dart';

/// Contents of the map filter panel (time filter, type filter, track toggle).
///
/// Intended to be embedded inside a [MeridianBottomSheet] or a compact
/// [AlertDialog] (desktop). State is owned locally so the toggle and dropdown
/// update immediately without requiring the parent to rebuild the sheet.
/// Changes are forwarded via callbacks so the parent can persist state.
class MapFilterPanel extends StatefulWidget {
  const MapFilterPanel({
    super.key,
    required this.currentMaxAgeMinutes,
    required this.showTracks,
    required this.onMaxAgeChanged,
    required this.onShowTracksChanged,
    required this.currentHiddenTypes,
    required this.onHiddenTypesChanged,
    this.visibleStationCount = 0,
    this.totalStationCount = 0,
  });

  /// Currently active station timeout in minutes, or null for no limit.
  final int? currentMaxAgeMinutes;

  /// Whether track polylines are currently rendered.
  final bool showTracks;

  /// Called when the user selects a new timeout value.
  final ValueChanged<int?> onMaxAgeChanged;

  /// Called when the user toggles the track display.
  final ValueChanged<bool> onShowTracksChanged;

  /// Station types currently hidden on the map.
  final Set<StationType> currentHiddenTypes;

  /// Called when the hidden-type set changes.
  final ValueChanged<Set<StationType>> onHiddenTypesChanged;

  /// Number of stations passing the current display filter.
  final int visibleStationCount;

  /// Total number of known stations (unfiltered).
  final int totalStationCount;

  static const _timeOptions = <({String label, int? value})>[
    (label: '15 min', value: 15),
    (label: '30 min', value: 30),
    (label: '1 hour', value: 60),
    (label: '2 hours', value: 120),
    (label: '6 hours', value: 360),
    (label: '12 hours', value: 720),
    (label: 'No limit', value: null),
  ];

  static String labelFor(int? value) => _timeOptions
      .firstWhere((o) => o.value == value, orElse: () => _timeOptions[2])
      .label;

  @override
  State<MapFilterPanel> createState() => _MapFilterPanelState();
}

class _MapFilterPanelState extends State<MapFilterPanel> {
  late int? _maxAgeMinutes;
  late bool _showTracks;
  late Set<StationType> _hiddenTypes;

  @override
  void initState() {
    super.initState();
    _maxAgeMinutes = widget.currentMaxAgeMinutes;
    _showTracks = widget.showTracks;
    _hiddenTypes = Set.of(widget.currentHiddenTypes);
  }

  @override
  void didUpdateWidget(covariant MapFilterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentMaxAgeMinutes != widget.currentMaxAgeMinutes) {
      _maxAgeMinutes = widget.currentMaxAgeMinutes;
    }
    if (oldWidget.showTracks != widget.showTracks) {
      _showTracks = widget.showTracks;
    }
    if (oldWidget.currentHiddenTypes != widget.currentHiddenTypes) {
      _hiddenTypes = Set.of(widget.currentHiddenTypes);
    }
  }

  bool get _isNonDefault =>
      _maxAgeMinutes != 60 || !_showTracks || _hiddenTypes.isNotEmpty;

  void _resetToDefaults() {
    setState(() {
      _maxAgeMinutes = 60;
      _showTracks = true;
      _hiddenTypes = {};
    });
    widget.onMaxAgeChanged(60);
    widget.onShowTracksChanged(true);
    widget.onHiddenTypesChanged({});
  }

  void _toggleType(StationType type) {
    setState(() {
      if (_hiddenTypes.contains(type)) {
        _hiddenTypes.remove(type);
      } else {
        _hiddenTypes.add(type);
      }
    });
    widget.onHiddenTypesChanged(Set.of(_hiddenTypes));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'MAP FILTERS',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              if (widget.totalStationCount > 0)
                Text(
                  widget.visibleStationCount < widget.totalStationCount
                      ? '${widget.visibleStationCount} of ${widget.totalStationCount} stations'
                      : '${widget.totalStationCount} stations',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        ListTile(
          leading: const Icon(Symbols.schedule),
          title: const Text('Station timeout'),
          subtitle: const Text('Hide stations not heard within this window'),
          trailing: DropdownButton<int?>(
            value: _maxAgeMinutes,
            underline: const SizedBox.shrink(),
            items: MapFilterPanel._timeOptions
                .map(
                  (o) => DropdownMenuItem<int?>(
                    value: o.value,
                    child: Text(o.label),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v == _maxAgeMinutes) return;
              setState(() => _maxAgeMinutes = v);
              widget.onMaxAgeChanged(v);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            'STATION TYPES',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _typeChip(StationType.weather, Symbols.thunderstorm, 'Weather'),
              _typeChip(StationType.mobile, Symbols.directions_car, 'Mobile'),
              _typeChip(StationType.fixed, Symbols.home, 'Fixed'),
              _typeChip(StationType.object, Symbols.location_on, 'Object'),
              _typeChip(StationType.other, Symbols.more_horiz, 'Other'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          secondary: const Icon(Symbols.route),
          title: const Text('Show tracks'),
          subtitle: const Text('Render movement trails for mobile stations'),
          value: _showTracks,
          onChanged: (v) {
            setState(() => _showTracks = v);
            widget.onShowTracksChanged(v);
          },
        ),
        if (_isNonDefault)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: TextButton.icon(
              icon: const Icon(Symbols.restart_alt, size: 18),
              label: const Text('Reset to defaults'),
              onPressed: _resetToDefaults,
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _typeChip(StationType type, IconData icon, String label) {
    final selected = !_hiddenTypes.contains(type);
    return FilterChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      selected: selected,
      onSelected: (_) => _toggleType(type),
    );
  }
}
