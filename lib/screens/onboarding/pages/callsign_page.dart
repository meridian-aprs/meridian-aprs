import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../core/connection/aprs_is_connection.dart';
import '../../../core/connection/connection_registry.dart';
import '../../../services/station_settings_service.dart';
import '../../../ui/widgets/callsign_field.dart';

const String _kVersion = '0.1.0';

/// Onboarding step 3 (licensed path only) — callsign, SSID, passcode.
class CallsignPage extends StatefulWidget {
  const CallsignPage({super.key, required this.onNext, required this.onBack});

  /// Advance to the next onboarding step.
  final VoidCallback onNext;

  /// Go back to the previous step.
  final VoidCallback onBack;

  @override
  State<CallsignPage> createState() => _CallsignPageState();
}

class _CallsignPageState extends State<CallsignPage> {
  final _formKey = GlobalKey<FormState>();
  final _callsignController = TextEditingController();
  final _passcodeController = TextEditingController();
  int _ssid = 0;
  bool _callsignValid = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<StationSettingsService>();
    _callsignController.text = settings.callsign;
    _passcodeController.text = settings.passcode;
    _ssid = settings.ssid;
    _callsignValid = kAmateurCallsignRegex.hasMatch(settings.callsign.trim());
    _callsignController.addListener(_onCallsignChanged);
  }

  void _onCallsignChanged() {
    final valid = kAmateurCallsignRegex.hasMatch(
      _callsignController.text.trim(),
    );
    if (valid != _callsignValid) {
      setState(() => _callsignValid = valid);
    } else {
      // Still rebuild to refresh the live preview.
      setState(() {});
    }
  }

  @override
  void dispose() {
    _callsignController.removeListener(_onCallsignChanged);
    _callsignController.dispose();
    _passcodeController.dispose();
    super.dispose();
  }

  String _ssidLabel(int ssid) {
    // Common APRS SSID conventions (N5UWY / WB4APR usage guidelines).
    switch (ssid) {
      case 0:
        return '0 — Primary / home';
      case 1:
        return '1 — Additional home station';
      case 2:
        return '2 — Additional home station';
      case 3:
        return '3 — Additional home station';
      case 4:
        return '4 — Additional home station';
      case 5:
        return '5 — Other networks (D-STAR, etc.)';
      case 6:
        return '6 — Special / events';
      case 7:
        return '7 — Handheld';
      case 8:
        return '8 — Boat / maritime mobile';
      case 9:
        return '9 — Mobile (vehicle)';
      case 10:
        return '10 — Internet / IGate';
      case 11:
        return '11 — Balloons / aircraft';
      case 12:
        return '12 — Portable / tracker';
      case 13:
        return '13 — Weather station';
      case 14:
        return '14 — Trucker';
      case 15:
        return '15 — Digipeater';
      default:
        return '$ssid';
    }
  }

  String get _previewCallsign {
    final cs = _callsignController.text.trim().toUpperCase();
    if (cs.isEmpty) return 'CALLSIGN';
    return _ssid > 0 ? '$cs-$_ssid' : cs;
  }

  Future<void> _onNext() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final callsign = _callsignController.text.trim().toUpperCase();
    final passcode = _passcodeController.text.trim();
    final ssidSuffix = _ssid > 0 ? '-$_ssid' : '';
    final effectivePasscode = passcode.isEmpty ? '-1' : passcode;

    final stationSettings = context.read<StationSettingsService>();
    await stationSettings.setCallsign(callsign);
    await stationSettings.setSsid(_ssid);
    await stationSettings.setPasscode(passcode);

    if (!mounted) return;

    // Update APRS-IS credentials so the login line reflects the new callsign.
    final registry = context.read<ConnectionRegistry>();
    final aprsIsConn = registry.byId('aprs_is');
    if (aprsIsConn is AprsIsConnection) {
      try {
        aprsIsConn.updateCredentials(
          loginLine:
              'user $callsign$ssidSuffix pass $effectivePasscode vers meridian-aprs $_kVersion\r\n',
        );
      } catch (_) {
        // Safe to ignore — credentials will be applied on next connect.
      }
    }

    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your callsign',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your amateur radio callsign so Meridian can identify '
                'you on the APRS network.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              CallsignField(controller: _callsignController),
              const SizedBox(height: 8),
              // Live preview
              AnimatedOpacity(
                opacity: _callsignController.text.trim().isNotEmpty ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Text(
                  _previewCallsign,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: _ssid,
                decoration: const InputDecoration(
                  labelText: 'SSID',
                  border: OutlineInputBorder(),
                ),
                items: List.generate(16, (i) => i)
                    .map(
                      (i) => DropdownMenuItem(
                        value: i,
                        child: Text(_ssidLabel(i)),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _ssid = v);
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passcodeController,
                keyboardType: TextInputType.number,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'APRS-IS Passcode',
                  hintText: 'APRS-IS passcode (optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Symbols.lock),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "Required for transmitting via APRS-IS. Leave blank if you "
                "don't plan to use APRS-IS.",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _callsignValid ? _onNext : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Next'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
