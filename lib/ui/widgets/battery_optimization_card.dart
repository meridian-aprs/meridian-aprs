import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../theme/meridian_colors.dart';

/// Inline warning card prompting the user to opt Meridian out of Doze battery
/// optimization. Renders only when:
///   - Running on Android (no-op everywhere else).
///   - The runtime permission is currently DENIED.
///
/// Tapping the action opens the system "ignore battery optimization" dialog
/// via [Permission.ignoreBatteryOptimizations.request]. Re-checks the state
/// when the app returns to the foreground so the card disappears as soon as
/// the user grants the exemption from system settings.
///
/// Used on the Connection screen's BLE tab and (eventually) anywhere else
/// reliable background BLE matters.
class BatteryOptimizationCard extends StatefulWidget {
  const BatteryOptimizationCard({super.key, this.checker});

  /// Test seam — overrides the platform permission check. The default reads
  /// [Permission.ignoreBatteryOptimizations] on Android and returns granted
  /// on every other platform. Returning `true` means the exemption is in
  /// place (and the card collapses).
  final Future<bool> Function()? checker;

  @override
  State<BatteryOptimizationCard> createState() =>
      _BatteryOptimizationCardState();
}

class _BatteryOptimizationCardState extends State<BatteryOptimizationCard>
    with WidgetsBindingObserver {
  bool? _ignored;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final granted = await (widget.checker ?? _defaultChecker)();
    if (!mounted) return;
    setState(() => _ignored = granted);
  }

  static Future<bool> _defaultChecker() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    final status = await Permission.ignoreBatteryOptimizations.status;
    return status.isGranted;
  }

  Future<void> _request() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await Permission.ignoreBatteryOptimizations.request();
    } catch (_) {
      // Permission_handler can throw on rare OEM quirks; refresh and continue.
    }
    // Always re-check; the system dialog may have been dismissed without
    // a grant, in which case the card should remain visible.
    await _refresh();
    if (!mounted) return;
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    // Hide everywhere the prompt is meaningless or already satisfied.
    if (_ignored == null || _ignored == true) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final warning = MeridianColors.warning;

    return Card(
      margin: EdgeInsets.zero,
      color: warning.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: warning.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Symbols.battery_alert, color: warning, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Battery optimization is on',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'When Android puts Meridian to sleep, the BLE TNC link can drop '
              'and stay disconnected until you open the app again. Allow '
              'Meridian to ignore battery optimization to keep beaconing and '
              'reconnect timers running while the screen is off.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: _busy ? null : _request,
                icon: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Symbols.tune),
                label: const Text('Allow'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
