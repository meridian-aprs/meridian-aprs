import 'package:flutter/material.dart';

import '../../ui/widgets/callsign_field.dart';

/// Second onboarding page — callsign, SSID, and APRS-IS passcode entry.
class OnboardingCallsignPage extends StatefulWidget {
  const OnboardingCallsignPage({super.key, required this.onNext});

  /// Called when the user validates input and taps "Next".
  /// Provides the entered [callsign], [ssid], and [passcode].
  final void Function(String callsign, int ssid, String passcode) onNext;

  @override
  State<OnboardingCallsignPage> createState() => _OnboardingCallsignPageState();
}

class _OnboardingCallsignPageState extends State<OnboardingCallsignPage> {
  final _formKey = GlobalKey<FormState>();
  final _callsignController = TextEditingController();
  final _passcodeController = TextEditingController();
  int _ssid = 0;

  @override
  void dispose() {
    _callsignController.dispose();
    _passcodeController.dispose();
    super.dispose();
  }

  String _ssidLabel(int ssid) {
    switch (ssid) {
      case 0:
        return '0 — Primary station';
      case 7:
        return '7 — Handheld';
      case 9:
        return '9 — Mobile';
      case 12:
        return '12 — Portable';
      default:
        return '$ssid — (generic)';
    }
  }

  void _onNext() {
    if (_formKey.currentState?.validate() ?? false) {
      widget.onNext(
        _callsignController.text.trim().toUpperCase(),
        _ssid,
        _passcodeController.text.trim(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your Callsign',
                style: theme.textTheme.headlineMedium?.copyWith(
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
              // Callsign field with inline validation.
              CallsignField(controller: _callsignController),
              const SizedBox(height: 16),
              // SSID dropdown.
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
              // APRS-IS passcode.
              TextFormField(
                controller: _passcodeController,
                keyboardType: TextInputType.number,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'APRS-IS Passcode',
                  hintText: 'Leave blank for receive-only',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 8),
              // Inline explainer.
              ExpansionTile(
                title: const Text("What's this?"),
                tilePadding: EdgeInsets.zero,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Your APRS-IS passcode is a hash derived from your '
                      'callsign. It allows you to send packets via APRS-IS. '
                      'For receive-only use, leave it blank.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _onNext,
                  style: ElevatedButton.styleFrom(
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
