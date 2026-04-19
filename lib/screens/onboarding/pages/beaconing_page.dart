import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

  Future<void> _onFinish() async {
    setState(() => _finishing = true);
    if (_beaconingEnabled) {
      final beaconingService = context.read<BeaconingService>();
      await beaconingService.setMode(_mode);
      await beaconingService.setAutoInterval(_intervalSeconds);
      await beaconingService.startBeaconing();
    }
    if (mounted) widget.onFinish();
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
