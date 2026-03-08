import 'package:flutter/material.dart';

/// A validated text form field for amateur radio callsign entry.
///
/// Validates against the standard amateur callsign regex:
/// 1–2 prefix letters, one digit, 1–3 suffix letters, optional SSID (-0 to -15).
///
/// Validation fires on user interaction via
/// [AutovalidateMode.onUserInteraction] — no submit required to see errors.
class CallsignField extends StatelessWidget {
  const CallsignField({
    super.key,
    required this.controller,
    this.onChanged,
    this.label = 'Callsign',
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String label;

  // SSID is optional (-0 to -15).
  static final _callsignRegex = RegExp(
    r'^[A-Za-z]{1,2}[0-9][A-Za-z]{1,3}(-[0-9]{1,2})?$',
  );

  String? _validate(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Callsign is required';
    }
    if (!_callsignRegex.hasMatch(value.trim())) {
      return 'Invalid callsign format';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
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
