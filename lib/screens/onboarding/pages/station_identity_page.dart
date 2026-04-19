import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/station_settings_service.dart';
import '../../../ui/widgets/aprs_symbol_widget.dart';
import '../../../ui/widgets/symbol_picker_dialog.dart';

/// Onboarding step 5 — station symbol and comment.
class StationIdentityPage extends StatefulWidget {
  const StationIdentityPage({
    super.key,
    required this.onNext,
    required this.onBack,
  });

  /// Advance to the next onboarding step.
  final VoidCallback onNext;

  /// Go back to the previous step.
  final VoidCallback onBack;

  @override
  State<StationIdentityPage> createState() => _StationIdentityPageState();
}

class _StationIdentityPageState extends State<StationIdentityPage> {
  final _commentController = TextEditingController();
  late String _symbolTable;
  late String _symbolCode;

  @override
  void initState() {
    super.initState();
    final settings = context.read<StationSettingsService>();
    _symbolTable = settings.symbolTable;
    _symbolCode = settings.symbolCode;
    _commentController.text = settings.comment;
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _pickSymbol() async {
    final result = await showDialog<AprsSymbolEntry>(
      context: context,
      builder: (_) => SymbolPickerDialog(
        currentTable: _symbolTable,
        currentCode: _symbolCode,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _symbolTable = result.table;
        _symbolCode = result.code;
      });
      await context.read<StationSettingsService>().setSymbol(
        result.table,
        result.code,
      );
    }
  }

  Future<void> _onNext() async {
    final comment = _commentController.text;
    final current = context.read<StationSettingsService>().comment;
    if (comment != current) {
      await context.read<StationSettingsService>().setComment(comment);
    }
    if (!mounted) return;
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your station',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a symbol and optional comment that other operators '
              'will see on the APRS network.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),

            // Symbol picker row
            Text(
              'Station symbol',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    border: Border.all(color: colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: AprsSymbolWidget(
                    symbolTable: _symbolTable,
                    symbolCode: _symbolCode,
                    size: 40,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      symbolName(_symbolTable, _symbolCode),
                      style: theme.textTheme.bodyLarge,
                    ),
                    Text(
                      '$_symbolTable$_symbolCode',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                OutlinedButton(
                  onPressed: _pickSymbol,
                  child: const Text('Change'),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // Comment field
            Text(
              'Station comment',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _commentController,
              maxLength: 36,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'e.g. Mobile — 145.520 MHz',
                border: const OutlineInputBorder(),
                counterText: '${_commentController.text.length}/36',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _onNext,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
