import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../core/connection/aprs_is_connection.dart';
import '../../../core/connection/aprs_is_filter_config.dart';
import '../../../core/connection/connection_registry.dart';
import '../../../services/station_service.dart';
import '../../../services/station_settings_service.dart';
import '../../../ui/utils/distance_formatter.dart';
import '../advanced_mode_controller.dart';
import '../widgets/section_header.dart';

class ConnectionsSettingsContent extends StatefulWidget {
  const ConnectionsSettingsContent({super.key});

  @override
  State<ConnectionsSettingsContent> createState() =>
      _ConnectionsSettingsContentState();
}

class _ConnectionsSettingsContentState
    extends State<ConnectionsSettingsContent> {
  void _selectPreset(AprsIsFilterPreset preset) {
    final settings = context.read<StationSettingsService>();
    final next = AprsIsFilterConfig.fromPreset(preset);
    if (next != null) {
      settings.setAprsIsFilter(next);
      return;
    }
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
    settings.setAprsIsFilterCustom(updated);
  }

  Future<void> _showServerOverrideDialog(
    BuildContext context,
    AprsIsConnection conn,
    bool isConnected,
  ) async {
    final ctrl = TextEditingController(
      text: conn.hasServerOverride ? conn.serverDisplay : '',
    );
    String? error;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('APRS-IS server'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                decoration: InputDecoration(
                  labelText: 'host:port',
                  hintText: 'rotate.aprs2.net:14580',
                  border: const OutlineInputBorder(),
                  errorText: error,
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await conn.setServerOverride(null);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Reset to default'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final value = ctrl.text.trim();
                final valid = RegExp(
                  r'^[A-Za-z0-9.\-]+:\d{1,5}$',
                ).hasMatch(value);
                if (!valid) {
                  setDlgState(() => error = 'Enter a valid host:port');
                  return;
                }
                await conn.setServerOverride(value);
                if (ctx.mounted) Navigator.pop(ctx);
                if (isConnected && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Server change will apply on next connection',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
  }

  Future<void> _showServerOverrideDialogIos(
    BuildContext context,
    AprsIsConnection conn,
    bool isConnected,
  ) async {
    final ctrl = TextEditingController(
      text: conn.hasServerOverride ? conn.serverDisplay : '',
    );
    String? error;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('APRS-IS server'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                decoration: InputDecoration(
                  labelText: 'host:port',
                  hintText: 'rotate.aprs2.net:14580',
                  border: const OutlineInputBorder(),
                  errorText: error,
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await conn.setServerOverride(null);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Reset to default'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final value = ctrl.text.trim();
                final valid = RegExp(
                  r'^[A-Za-z0-9.\-]+:\d{1,5}$',
                ).hasMatch(value);
                if (!valid) {
                  setDlgState(() => error = 'Enter a valid host:port');
                  return;
                }
                await conn.setServerOverride(value);
                if (ctx.mounted) Navigator.pop(ctx);
                if (isConnected && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Server change will apply on next connection',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<StationSettingsService>();
    final imperial = context.watch<StationService>().useImperialUnits;
    final advanced = context.watch<AdvancedModeController>();
    final registry = context.watch<ConnectionRegistry>();
    final theme = Theme.of(context);
    final config = settings.aprsIsFilter;

    final aprsIsConn = kIsWeb
        ? null
        : registry.byId('aprs_is') as AprsIsConnection?;
    final isConnected = aprsIsConn?.isConnected ?? false;

    final basicSegments = <ButtonSegment<AprsIsFilterPreset>>[
      const ButtonSegment(
        value: AprsIsFilterPreset.local,
        label: Text('Local'),
      ),
      const ButtonSegment(
        value: AprsIsFilterPreset.regional,
        label: Text('Regional'),
      ),
      const ButtonSegment(value: AprsIsFilterPreset.wide, label: Text('Wide')),
    ];
    final allSegments = [
      ...basicSegments,
      const ButtonSegment(
        value: AprsIsFilterPreset.custom,
        label: Text('Custom'),
      ),
    ];

    final showCustomActive =
        !advanced.isEnabled && config.preset == AprsIsFilterPreset.custom;

    return ListView(
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
          child: SegmentedButton<AprsIsFilterPreset>(
            segments: advanced.isEnabled ? allSegments : basicSegments,
            selected: showCustomActive ? {} : {config.preset},
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            onSelectionChanged: (selected) {
              if (selected.isNotEmpty) _selectPreset(selected.first);
            },
          ),
        ),
        if (showCustomActive) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Symbols.info, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Custom filter values are active. Enable Advanced User Mode to configure.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (advanced.isEnabled) ...[
          const SizedBox(height: 8),
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
        if (!kIsWeb && aprsIsConn != null && advanced.isEnabled) ...[
          const SectionHeader('Server'),
          ListTile(
            leading: const Icon(Symbols.dns),
            title: const Text('APRS-IS server'),
            subtitle: Text(aprsIsConn.serverDisplay),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              if (!kIsWeb && Platform.isIOS) {
                _showServerOverrideDialogIos(context, aprsIsConn, isConnected);
              } else {
                _showServerOverrideDialog(context, aprsIsConn, isConnected);
              }
            },
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}

class _PadSlider extends StatelessWidget {
  const _PadSlider({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final pct = (value * 100).round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
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
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
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
            divisions: 49,
            value: km.toDouble().clamp(10, 500),
            label: formatRadiusKm(km, imperial: imperial),
            onChanged: (v) {
              final snapped = (v / 10).round() * 10;
              onChanged(snapped.toDouble());
            },
          ),
        ],
      ),
    );
  }
}
