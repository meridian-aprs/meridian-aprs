/// Reusable APRS symbol picker dialog.
///
/// Extracted from [SettingsScreen] so that onboarding and other screens can
/// present the same symbol chooser without importing the full settings widget.
library;

import 'package:flutter/material.dart';

import 'aprs_symbol_widget.dart';

/// A single APRS symbol entry with a human-readable name.
class AprsSymbolEntry {
  const AprsSymbolEntry(this.table, this.code, this.name);

  final String table;
  final String code;
  final String name;
}

/// Curated list of common APRS symbols.
const kAprsSymbols = <AprsSymbolEntry>[
  AprsSymbolEntry('/', '>', 'Car'),
  AprsSymbolEntry('/', '-', 'House'),
  AprsSymbolEntry('/', '[', 'Person / Runner'),
  AprsSymbolEntry('/', '<', 'Motorcycle'),
  AprsSymbolEntry('/', 'b', 'Bicycle'),
  AprsSymbolEntry('/', 'k', 'Truck'),
  AprsSymbolEntry('/', 'u', 'Semi Truck'),
  AprsSymbolEntry('/', 'U', 'Bus'),
  AprsSymbolEntry('/', 'j', 'Jeep'),
  AprsSymbolEntry('/', 'v', 'Van'),
  AprsSymbolEntry('/', 'X', 'Helicopter'),
  AprsSymbolEntry('/', '^', 'Aircraft'),
  AprsSymbolEntry('/', "'", 'Small Aircraft'),
  AprsSymbolEntry('/', 'O', 'Balloon'),
  AprsSymbolEntry('/', 'Y', 'Sailboat'),
  AprsSymbolEntry('/', 's', 'Powerboat'),
  AprsSymbolEntry('/', '_', 'Weather Station'),
  AprsSymbolEntry('/', '#', 'Digipeater'),
  AprsSymbolEntry('/', 'r', 'Repeater Tower'),
  AprsSymbolEntry('/', 'a', 'Ambulance'),
  AprsSymbolEntry('/', 'h', 'Hospital'),
  AprsSymbolEntry('/', 'f', 'Fire Truck'),
  AprsSymbolEntry('/', 'd', 'Fire Department'),
  AprsSymbolEntry('/', 'P', 'Police'),
  AprsSymbolEntry('/', '!', 'Emergency'),
  AprsSymbolEntry('/', '+', 'Red Cross'),
  AprsSymbolEntry('/', '@', 'Hurricane'),
  AprsSymbolEntry('/', 'R', 'Recreational Vehicle'),
  AprsSymbolEntry('/', 'n', 'Network Node'),
  AprsSymbolEntry('/', '&', 'Gateway'),
  AprsSymbolEntry('/', r'$', 'Phone'),
  AprsSymbolEntry('\\', '-', 'House (overlay)'),
  AprsSymbolEntry('\\', '>', 'Car (overlay)'),
  AprsSymbolEntry('\\', '[', 'Person (overlay)'),
];

/// Returns a human-readable name for [table]+[code], or a fallback string.
String symbolName(String table, String code) {
  for (final s in kAprsSymbols) {
    if (s.table == table && s.code == code) return s.name;
  }
  return 'Custom ($table$code)';
}

/// Searchable dialog that lets the user choose an APRS symbol.
///
/// Returns the selected [AprsSymbolEntry], or `null` when cancelled.
class SymbolPickerDialog extends StatefulWidget {
  const SymbolPickerDialog({
    super.key,
    required this.currentTable,
    required this.currentCode,
  });

  final String currentTable;
  final String currentCode;

  @override
  State<SymbolPickerDialog> createState() => _SymbolPickerDialogState();
}

class _SymbolPickerDialogState extends State<SymbolPickerDialog> {
  final _searchCtrl = TextEditingController();
  List<AprsSymbolEntry> _filtered = kAprsSymbols;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch(String query) {
    final q = query.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? kAprsSymbols
          : kAprsSymbols
                .where((s) => s.name.toLowerCase().contains(q))
                .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Choose Symbol', style: theme.textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: _onSearch,
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 380),
            child: _filtered.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No symbols found.'),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _filtered.length,
                    itemBuilder: (context, index) {
                      final entry = _filtered[index];
                      final isSelected =
                          entry.table == widget.currentTable &&
                          entry.code == widget.currentCode;
                      return ListTile(
                        dense: true,
                        leading: AprsSymbolWidget(
                          symbolTable: entry.table,
                          symbolCode: entry.code,
                          size: 24,
                        ),
                        title: Text(entry.name),
                        subtitle: Text(
                          '${entry.table}${entry.code}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        selected: isSelected,
                        selectedTileColor: theme.colorScheme.primaryContainer
                            .withValues(alpha: 0.3),
                        onTap: () => Navigator.of(context).pop(entry),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
