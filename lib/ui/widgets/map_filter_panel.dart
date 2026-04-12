import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Contents of the map filter panel (time filter + track toggle).
///
/// Intended to be embedded inside a [MeridianBottomSheet] or a compact
/// [AlertDialog] (desktop). The panel is pure UI — all state changes are
/// forwarded via callbacks so the parent can own the state.
class MapFilterPanel extends StatelessWidget {
  const MapFilterPanel({
    super.key,
    required this.currentMaxAgeMinutes,
    required this.showTracks,
    required this.onMaxAgeChanged,
    required this.onShowTracksChanged,
  });

  /// Currently active station timeout in minutes, or null for no limit.
  final int? currentMaxAgeMinutes;

  /// Whether track polylines are currently rendered.
  final bool showTracks;

  /// Called when the user selects a new timeout value.
  final ValueChanged<int?> onMaxAgeChanged;

  /// Called when the user toggles the track display.
  final ValueChanged<bool> onShowTracksChanged;

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
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'MAP FILTERS',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Symbols.schedule),
          title: const Text('Station timeout'),
          subtitle: const Text('Hide stations not heard within this window'),
          trailing: DropdownButton<int?>(
            value: currentMaxAgeMinutes,
            underline: const SizedBox.shrink(),
            items: _timeOptions
                .map(
                  (o) => DropdownMenuItem<int?>(
                    value: o.value,
                    child: Text(o.label),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != currentMaxAgeMinutes) onMaxAgeChanged(v);
            },
          ),
        ),
        SwitchListTile.adaptive(
          secondary: const Icon(Symbols.route),
          title: const Text('Show tracks'),
          subtitle: const Text('Render movement trails for mobile stations'),
          value: showTracks,
          onChanged: onShowTracksChanged,
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
