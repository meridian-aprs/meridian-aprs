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
  final _pathController = TextEditingController(text: 'WIDE1-1,WIDE2-1');

  static const _intervalOptions = [
    (label: '1 min', seconds: 60),
    (label: '2 min', seconds: 120),
    (label: '5 min', seconds: 300),
    (label: '10 min', seconds: 600),
    (label: '30 min', seconds: 1800),
  ];

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _onFinish() async {
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
                const SizedBox(height: 16),

                // Advanced settings
                ExpansionTile(
                  title: const Text('Advanced'),
                  tilePadding: EdgeInsets.zero,
                  children: [
                    const SizedBox(height: 8),
                    if (_mode == BeaconMode.auto) ...[
                      Text(
                        'Interval',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        initialValue: _intervalSeconds,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: _intervalOptions
                            .map(
                              (o) => DropdownMenuItem(
                                value: o.seconds,
                                child: Text(o.label),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _intervalSeconds = v);
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    // TODO(v0.13): wire _pathController to BeaconingService once
                    // a setPath() setter is added there. Currently the field is
                    // display-only (default WIDE1-1,WIDE2-1 is used at transmit
                    // time via AprsEncoder) — the value entered here is not
                    // persisted.
                    TextFormField(
                      controller: _pathController,
                      decoration: const InputDecoration(
                        labelText: 'APRS path',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ],
            ],

            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _onFinish,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(
                  _beaconingEnabled ? 'Start Listening' : 'Go to Map',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
