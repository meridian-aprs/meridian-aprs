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
import '../smart_beaconing_params_screen.dart';
import '../widgets/section_header.dart';

class BeaconingSection extends StatelessWidget {
  const BeaconingSection({super.key});

  @override
  Widget build(BuildContext context) {
    final beaconing = context.watch<BeaconingService>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
          _IntervalTile(
            intervalS: beaconing.autoIntervalS,
            onChanged: (v) =>
                context.read<BeaconingService>().setAutoInterval(v),
          ),
        ],
        if (beaconing.mode == BeaconMode.smart) ...[
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
      ],
    );
  }
}

/// iOS-only widget that watches [IosBackgroundService] and shows a
/// [CupertinoAlertDialog] when background location permission is needed.
/// Renders nothing visible; exists only to host the listener lifecycle.
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

class _IntervalTile extends StatelessWidget {
  const _IntervalTile({required this.intervalS, required this.onChanged});

  final int intervalS;
  final ValueChanged<int> onChanged;

  static String _label(int minutes) =>
      minutes == 1 ? '1 minute' : '$minutes minutes';

  @override
  Widget build(BuildContext context) {
    // Snap any stored value to the nearest whole minute (1–60).
    final minutes = (intervalS / 60).round().clamp(1, 60);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: const Text('Beacon Interval'),
          subtitle: Text(_label(minutes)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Slider(
            min: 1,
            max: 60,
            divisions: 59,
            value: minutes.toDouble(),
            label: _label(minutes),
            onChanged: (v) => onChanged(v.round() * 60),
          ),
        ),
      ],
    );
  }
}
