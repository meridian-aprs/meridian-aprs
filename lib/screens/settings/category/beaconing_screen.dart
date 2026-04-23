import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../services/background_service_manager.dart';
import '../../../services/beaconing_service.dart';
import '../../../services/ios_background_service.dart';
import '../../../theme/meridian_colors.dart';
import '../../../ui/utils/platform_route.dart';
import '../advanced_mode_controller.dart';
import '../smart_beaconing_params_screen.dart';
import '../widgets/section_header.dart';

class BeaconingSettingsContent extends StatelessWidget {
  const BeaconingSettingsContent({super.key});

  @override
  Widget build(BuildContext context) {
    final beaconing = context.watch<BeaconingService>();
    final advanced = context.watch<AdvancedModeController>();

    return ListView(
      children: [
        const SectionHeader('Beaconing'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              const Text('Mode'),
              const SizedBox(width: 16),
              SegmentedButton<BeaconMode>(
                segments: const [
                  ButtonSegment(
                    value: BeaconMode.manual,
                    icon: Icon(Symbols.touch_app),
                    label: Text('Manual'),
                  ),
                  ButtonSegment(
                    value: BeaconMode.auto,
                    icon: Icon(Symbols.timer),
                    label: Text('Auto'),
                  ),
                  ButtonSegment(
                    value: BeaconMode.smart,
                    icon: Icon(Symbols.route),
                    label: Text('Smart'),
                  ),
                ],
                selected: {beaconing.mode},
                onSelectionChanged: (modes) {
                  if (modes.isNotEmpty) {
                    context.read<BeaconingService>().setMode(modes.first);
                  }
                },
              ),
            ],
          ),
        ),
        if (beaconing.mode == BeaconMode.auto) ...[
          _DiscreteIntervalTile(
            intervalS: beaconing.autoIntervalS,
            onChanged: (v) =>
                context.read<BeaconingService>().setAutoInterval(v),
          ),
        ],
        if (beaconing.mode == BeaconMode.smart && advanced.isEnabled) ...[
          ListTile(
            title: const Text('SmartBeaconing™ Parameters'),
            subtitle: Text(
              'Fast ${beaconing.smartParams.fastSpeedKmh.toInt()} km/h → '
              '${beaconing.smartParams.fastRateS}s  •  '
              'Slow ${beaconing.smartParams.slowSpeedKmh.toInt()} km/h → '
              '${beaconing.smartParams.slowRateS}s',
            ),
            trailing: const Icon(Symbols.chevron_right),
            onTap: () => Navigator.push(
              context,
              buildPlatformRoute((_) => const SmartBeaconingParamsScreen()),
            ),
          ),
        ],
        if (!kIsWeb && Platform.isIOS) const _IosBackgroundLocationPrompt(),
        if (!kIsWeb && Platform.isAndroid)
          Consumer<BackgroundServiceManager>(
            builder: (context, bsm, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  title: const Text('Background activity'),
                  subtitle: const Text(
                    'Keep beaconing active when the screen is locked.',
                  ),
                  value: bsm.backgroundActivityEnabled,
                  onChanged: (v) => context
                      .read<BackgroundServiceManager>()
                      .setBackgroundActivityEnabled(v),
                ),
                if (bsm.needsPermission && !bsm.isRunning)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        Icon(
                          Symbols.location_off,
                          size: 16,
                          color: MeridianColors.warning,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Background location permission needed to beacon '
                            'while the screen is locked.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: MeridianColors.warning),
                          ),
                        ),
                        TextButton(
                          onPressed: () => bsm.requestStartService(context),
                          child: const Text('Grant'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Discrete interval slider — 8 preset stops
// ---------------------------------------------------------------------------

class _DiscreteIntervalTile extends StatefulWidget {
  const _DiscreteIntervalTile({
    required this.intervalS,
    required this.onChanged,
  });

  final int intervalS;
  final ValueChanged<int> onChanged;

  static const _presets = [1, 2, 5, 10, 15, 20, 30, 60];

  static int _snapToPreset(int minutes) => _presets.reduce(
    (a, b) => (a - minutes).abs() <= (b - minutes).abs() ? a : b,
  );

  static String _label(int minutes) =>
      minutes == 1 ? '1 minute' : '$minutes minutes';

  @override
  State<_DiscreteIntervalTile> createState() => _DiscreteIntervalTileState();
}

class _DiscreteIntervalTileState extends State<_DiscreteIntervalTile> {
  bool _snapped = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_snapped) {
      _snapped = true;
      final minutes = (widget.intervalS / 60).round().clamp(1, 60);
      final snapped = _DiscreteIntervalTile._snapToPreset(minutes);
      if (snapped != minutes) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onChanged(snapped * 60);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final minutes = (widget.intervalS / 60).round().clamp(1, 60);
    final snapped = _DiscreteIntervalTile._snapToPreset(minutes);
    final index = _DiscreteIntervalTile._presets.indexOf(snapped);
    final safeIndex = index < 0 ? 0 : index;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: const Text('Beacon Interval'),
          subtitle: Text(_DiscreteIntervalTile._label(snapped)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Slider(
            min: 0,
            max: 7,
            divisions: 7,
            value: safeIndex.toDouble(),
            label: _DiscreteIntervalTile._label(snapped),
            onChanged: (v) {
              final preset = _DiscreteIntervalTile._presets[v.round()];
              widget.onChanged(preset * 60);
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// iOS-only background location prompt
// ---------------------------------------------------------------------------

class _IosBackgroundLocationPrompt extends StatefulWidget {
  const _IosBackgroundLocationPrompt();

  @override
  State<_IosBackgroundLocationPrompt> createState() =>
      _IosBackgroundLocationPromptState();
}

class _IosBackgroundLocationPromptState
    extends State<_IosBackgroundLocationPrompt> {
  late final IosBackgroundService _svc;

  @override
  void initState() {
    super.initState();
    _svc = context.read<IosBackgroundService>();
    _svc.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _svc.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (!mounted || !_svc.needsBackgroundLocationPrompt) return;
    _svc.clearBackgroundLocationPrompt();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showCupertinoDialog<void>(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: const Text('Background Location'),
          content: const Text(
            'To beacon your position while Meridian is in the background, '
            '"Always" location access is required. You can enable this in Settings.',
          ),
          actions: [
            CupertinoDialogAction(
              child: const Text('Not Now'),
              onPressed: () => Navigator.pop(context),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              child: const Text('Open Settings'),
              onPressed: () {
                Geolocator.openAppSettings();
                Navigator.pop(context);
              },
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
