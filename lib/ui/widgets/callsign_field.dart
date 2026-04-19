import 'package:flutter/material.dart';

/// Shared validation regex for an amateur callsign with an optional SSID.
///
/// Matches 1–2 prefix letters, one digit, 1–3 suffix letters, and an optional
/// `-0` to `-15` SSID suffix. Exposed here so other screens (e.g. the
/// onboarding callsign page) can validate without duplicating the pattern.
final RegExp kAmateurCallsignRegex = RegExp(
  r'^[A-Za-z]{1,2}[0-9][A-Za-z]{1,3}(-[0-9]{1,2})?$',
);

/// A validated text form field for amateur radio callsign entry.
///
/// Validates against [kAmateurCallsignRegex].
///
/// Validation fires on user interaction via
/// [AutovalidateMode.onUserInteraction] — no submit required to see errors.
class CallsignField extends StatelessWidget {
  const CallsignField({
    super.key,
    required this.controller,
    this.focusNode,
    this.onChanged,
    this.label = 'Callsign',
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final String label;

  String? _validate(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Callsign is required';
    }
    if (!kAmateurCallsignRegex.hasMatch(value.trim())) {
      return 'Invalid callsign format';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: _validate,
      onChanged: onChanged,
      textCapitalization: TextCapitalization.characters,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'e.g. W1ABC-9',
        prefixIcon: const Icon(Icons.radio),
        border: const OutlineInputBorder(),
      ),
    );
  }
}
