import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../../../services/background_service_manager.dart';
import '../../../services/beaconing_service.dart';
import '../../../services/station_settings_service.dart';

/// Onboarding step 7 (connection-configured path only) — basic beaconing setup.
class BeaconingPage extends StatefulWidget {
  const BeaconingPage({
    super.key,
    required this.onFinish,
    required this.onBack,
  });

  /// Complete onboarding and navigate to the map.
  final VoidCallback onFinish;

  /// Go back to the previous step.
  final VoidCallback onBack;

  @override
  State<BeaconingPage> createState() => _BeaconingPageState();
}

class _BeaconingPageState extends State<BeaconingPage> {
  bool _beaconingEnabled = false;
  BeaconMode _mode = BeaconMode.auto;
  int _intervalSeconds = 600;
  bool _finishing = false;

  static String _intervalLabel(int minutes) =>
      minutes == 1 ? '1 minute' : '$minutes minutes';

  bool get _needsBackgroundLocation =>
      _beaconingEnabled && _mode != BeaconMode.manual;

  bool get _canPromptBackgroundLocation =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> _onFinish() async {
    setState(() => _finishing = true);
    if (_beaconingEnabled) {
      final beaconingService = context.read<BeaconingService>();
      await beaconingService.setMode(_mode);
      await beaconingService.setAutoInterval(_intervalSeconds);
      await beaconingService.startBeaconing();

      if (!mounted) return;

      // Kick off the background-location flow. On Android, requestStartService
      // walks the user through when-in-use → background-location → notification.
      // On iOS, requestPermission() escalates WhenInUse → Always when the plist
      // has NSLocationAlwaysAndWhenInUseUsageDescription set.
      if (_needsBackgroundLocation && !kIsWeb) {
        if (Platform.isAndroid) {
          await context.read<BackgroundServiceManager>().requestStartService(
            context,
          );
        } else if (Platform.isIOS) {
          try {
            await Geolocator.requestPermission();
          } catch (_) {
            // Permission errors are non-fatal — user can grant later in Settings.
          }
        }
      }
    }
    if (mounted) widget.onFinish();
  }

  Future<void> _openSystemLocationSettings() async {
    try {
      await Geolocator.openAppSettings();
    } catch (_) {
      // Non-fatal — user can open Settings manually.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final stationSettings = context.read<StationSettingsService>();
    final isLicensed = stationSettings.isLicensed;
    final minutes = (_intervalSeconds / 60).round().clamp(1, 60);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Beaconing',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Beacons broadcast your position on the APRS network at a '
              'regular interval.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),

            // Licensed-only gate
            if (!isLicensed)
              Card(
                color: colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Beaconing requires a valid amateur radio license.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              SwitchListTile.adaptive(
                title: const Text('Enable beaconing'),
                subtitle: Text(
                  _beaconingEnabled
                      ? 'Your position will be broadcast automatically.'
                      : 'Beaconing is off.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                value: _beaconingEnabled,
                onChanged: (v) => setState(() => _beaconingEnabled = v),
                contentPadding: EdgeInsets.zero,
              ),

              if (_beaconingEnabled) ...[
                const SizedBox(height: 16),

                // Mode selector
                Text(
                  'Beacon mode',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<BeaconMode>(
                  segments: const [
                    ButtonSegment(
                      value: BeaconMode.manual,
                      label: Text('Manual'),
                    ),
                    ButtonSegment(value: BeaconMode.auto, label: Text('Auto')),
                    ButtonSegment(
                      value: BeaconMode.smart,
                      label: Text('Smart'),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),

                // Interval slider — Auto mode only
                if (_mode == BeaconMode.auto) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Interval',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        _intervalLabel(minutes),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    min: 1,
                    max: 60,
                    divisions: 59,
                    value: minutes.toDouble(),
                    label: _intervalLabel(minutes),
                    onChanged: (v) =>
                        setState(() => _intervalSeconds = v.round() * 60),
                  ),
                ],

                if (_needsBackgroundLocation &&
                    _canPromptBackgroundLocation) ...[
                  const SizedBox(height: 16),
                  _BackgroundLocationExplainer(
                    onOpenSettings: _openSystemLocationSettings,
                  ),
                ],
              ],
            ],

            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _finishing ? null : _onFinish,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _finishing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                        ),
                      )
                    : Text(_beaconingEnabled ? 'Start Beaconing' : 'Go to Map'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackgroundLocationExplainer extends StatelessWidget {
  const _BackgroundLocationExplainer({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isIos = !kIsWeb && Platform.isIOS;

    // iOS phrases the option as "Always Allow"; Android uses "Allow all the time".
    final optionLabel = isIos ? 'Always Allow' : 'Allow all the time';
    return Card(
      color: colorScheme.surfaceContainerHighest,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.my_location,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  'Background location',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "To keep beaconing when Meridian isn't on screen, your device "
              'needs "$optionLabel" location access. Tap Start Beaconing to '
              'grant it now, or open Settings if you already denied the '
              'prompt.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onOpenSettings,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open Settings'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
