/// Bottom sheet for composing a new APRS message thread.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../screens/message_thread_screen.dart';
import '../../services/message_service.dart';
import 'callsign_field.dart';
import '../utils/platform_route.dart';

class ComposeMessageSheet extends StatefulWidget {
  const ComposeMessageSheet({super.key, this.initialCallsign});

  /// Pre-fills the callsign field when composing a reply from a station tile.
  final String? initialCallsign;

  @override
  State<ComposeMessageSheet> createState() => _ComposeMessageSheetState();
}

class _ComposeMessageSheetState extends State<ComposeMessageSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _callsignCtrl;
  final _textCtrl = TextEditingController();

  static const _maxLength = 67;

  @override
  void initState() {
    super.initState();
    _callsignCtrl = TextEditingController(text: widget.initialCallsign ?? '');
  }

  @override
  void dispose() {
    _callsignCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  int get _remaining => _maxLength - _textCtrl.text.length;

  Future<void> _send() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_textCtrl.text.trim().isEmpty) return;

    final callsign = _callsignCtrl.text.trim().toUpperCase();
    final text = _textCtrl.text.trim();

    await context.read<MessageService>().sendMessage(callsign, text);
    if (!mounted) return;

    Navigator.of(context).pop();
    Navigator.push(
      context,
      buildPlatformRoute((_) => MessageThreadScreen(peerCallsign: callsign)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text('New Message', style: theme.textTheme.titleMedium),
          ),
          Form(
            key: _formKey,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CallsignField(
                    controller: _callsignCtrl,
                    label: 'To (callsign)',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _textCtrl,
                    decoration: InputDecoration(
                      labelText: 'Message',
                      border: const OutlineInputBorder(),
                      counterText: '',
                      suffix: Text(
                        '$_remaining',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: _remaining < 10
                              ? theme.colorScheme.error
                              : theme.colorScheme.outline,
                        ),
                      ),
                    ),
                    maxLength: _maxLength,
                    maxLines: 3,
                    onChanged: (_) => setState(() {}),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter a message'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    icon: const Icon(Symbols.send),
                    label: const Text('Send'),
                    onPressed: _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
