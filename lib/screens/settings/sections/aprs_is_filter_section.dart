import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../core/connection/aprs_is_filter_config.dart';
import '../../../services/station_service.dart';
import '../../../services/station_settings_service.dart';
import '../../../ui/utils/distance_formatter.dart';
import '../widgets/section_header.dart';

/// APRS-IS server-side filter settings (v0.13).
///
/// Surfaces the four preset tiers (Local / Regional / Wide / Custom) as a
/// [SegmentedButton], with an expandable "Advanced" section that reveals the
/// two underlying knobs: viewport pad and minimum radius.
///
/// Tweaking any advanced slider switches the active preset to
/// [AprsIsFilterPreset.custom] and persists both the custom preset flag and
/// the new tuple, so switching Regional → Custom → Regional → Custom restores
/// the user's last Custom values rather than Regional's.
class AprsIsFilterSection extends StatefulWidget {
  const AprsIsFilterSection({super.key});

  @override
  State<AprsIsFilterSection> createState() => _AprsIsFilterSectionState();
}

class _AprsIsFilterSectionState extends State<AprsIsFilterSection> {
  bool _advancedExpanded = false;

  void _selectPreset(AprsIsFilterPreset preset) {
    final settings = context.read<StationSettingsService>();
    final next = AprsIsFilterConfig.fromPreset(preset);
    if (next != null) {
      settings.setAprsIsFilter(next);
      return;
    }
    // Custom preset has no canonical tuple. Prefer the user's remembered
    // Custom tuple if they have ever tweaked one; otherwise seed Custom with
    // whatever the current active tuple is so the UI has sane starting
    // values.
    final config =
        settings.aprsIsFilterCustom ??
        settings.aprsIsFilter.copyWith(preset: AprsIsFilterPreset.custom);
    settings.setAprsIsFilter(config);
  }

  void _updateAdvanced({double? padPct, double? minRadiusKm}) {
    final settings = context.read<StationSettingsService>();
    final current = settings.aprsIsFilter;
    final updated = current.copyWith(
      preset: AprsIsFilterPreset.custom,
      padPct: padPct,
      minRadiusKm: minRadiusKm,
    );
    settings.setAprsIsFilter(updated);
    // Remember the user's Custom tuple separately so switching Custom →
    // Regional → Custom restores these values rather than Regional's.
    settings.setAprsIsFilterCustom(updated);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<StationSettingsService>();
    final imperial = context.watch<StationService>().useImperialUnits;
    final theme = Theme.of(context);
    final config = settings.aprsIsFilter;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('APRS-IS Filter'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            'Controls how many APRS stations are requested from the APRS-IS '
            'server based on your map viewport.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _PresetSelector(
            current: config.preset,
            onSelect: _selectPreset,
          ),
        ),
        const SizedBox(height: 4),
        Theme(
          // Flatten the ExpansionTile divider/padding so it sits naturally in
          // the settings ListView.
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: _advancedExpanded,
            onExpansionChanged: (v) => setState(() => _advancedExpanded = v),
            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            leading: const Icon(Symbols.tune),
            title: const Text('Advanced'),
            subtitle: Text(
              _advancedSummary(config, imperial: imperial),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            children: [
              _PadSlider(
                value: config.padPct,
                onChanged: (v) => _updateAdvanced(padPct: v),
              ),
              _MinRadiusSlider(
                value: config.minRadiusKm,
                imperial: imperial,
                onChanged: (v) => _updateAdvanced(minRadiusKm: v),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _advancedSummary(AprsIsFilterConfig config, {required bool imperial}) {
    final pad = '${(config.padPct * 100).round()}% pad';
    final radius = formatRadiusKm(
      config.minRadiusKm.round(),
      imperial: imperial,
    );
    return '$pad, $radius min';
  }
}

// ---------------------------------------------------------------------------
// Preset selector
// ---------------------------------------------------------------------------

class _PresetSelector extends StatelessWidget {
  const _PresetSelector({required this.current, required this.onSelect});

  final AprsIsFilterPreset current;
  final ValueChanged<AprsIsFilterPreset> onSelect;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<AprsIsFilterPreset>(
      segments: const [
        ButtonSegment(value: AprsIsFilterPreset.local, label: Text('Local')),
        ButtonSegment(
          value: AprsIsFilterPreset.regional,
          label: Text('Regional'),
        ),
        ButtonSegment(value: AprsIsFilterPreset.wide, label: Text('Wide')),
        ButtonSegment(value: AprsIsFilterPreset.custom, label: Text('Custom')),
      ],
      selected: {current},
      showSelectedIcon: false,
      onSelectionChanged: (selected) => onSelect(selected.first),
    );
  }
}

// ---------------------------------------------------------------------------
// Viewport pad slider (0–100%, step 5)
// ---------------------------------------------------------------------------

class _PadSlider extends StatelessWidget {
  const _PadSlider({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final pct = (value * 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [const Text('Viewport pad'), Text('$pct%')],
          ),
          Slider(
            min: 0,
            max: 100,
            divisions: 20,
            value: pct.toDouble(),
            label: '$pct%',
            onChanged: (v) => onChanged((v.round() / 100).toDouble()),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Minimum radius slider (10–500, step 10)
// ---------------------------------------------------------------------------

class _MinRadiusSlider extends StatelessWidget {
  const _MinRadiusSlider({
    required this.value,
    required this.imperial,
    required this.onChanged,
  });

  final double value;
  final bool imperial;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final km = value.round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Minimum radius'),
              Text(formatRadiusKm(km, imperial: imperial)),
            ],
          ),
          Slider(
            min: 10,
            max: 500,
            divisions: 49, // (500 - 10) / 10 = 49 steps
            value: km.toDouble().clamp(10, 500),
            label: formatRadiusKm(km, imperial: imperial),
            onChanged: (v) {
              // Snap to nearest 10 km.
              final snapped = (v / 10).round() * 10;
              onChanged(snapped.toDouble());
            },
          ),
        ],
      ),
    );
  }
}
