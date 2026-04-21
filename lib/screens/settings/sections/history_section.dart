import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../services/message_service.dart';
import '../../../services/station_service.dart';
import '../widgets/section_header.dart';

class HistorySection extends StatelessWidget {
  const HistorySection({super.key});

  // Day options: 0 is the sentinel for "forever".
  static const _dayOptions = [7, 14, 30, 90, 180, 365, 0];

  static String _label(int days) => days == 0 ? 'Forever' : '$days days';

  /// Snap [value] to the nearest option (handles defaults that may not be
  /// in the list, e.g. after an app update changes defaults).
  static int _snap(int value) => _dayOptions.reduce(
    (a, b) => (a - value).abs() <= (b - value).abs() ? a : b,
  );

  Widget _dayDropdown({
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return DropdownButton<int>(
      value: _snap(value),
      underline: const SizedBox.shrink(),
      items: _dayOptions
          .map((d) => DropdownMenuItem(value: d, child: Text(_label(d))))
          .toList(),
      onChanged: (d) {
        if (d != null) onChanged(d);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final stations = context.watch<StationService>();
    final messages = context.watch<MessageService>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('History'),

        // Packet log retention
        ListTile(
          title: const Text('Packet log'),
          subtitle: const Text('How long to keep received packets.'),
          trailing: _dayDropdown(
            value: stations.packetHistoryDays,
            onChanged: stations.setPacketHistoryDays,
          ),
        ),

        // Station history retention
        ListTile(
          title: const Text('Station history'),
          subtitle: const Text('How long to remember heard stations.'),
          trailing: _dayDropdown(
            value: stations.stationHistoryDays,
            onChanged: stations.setStationHistoryDays,
          ),
        ),

        // Message history retention
        ListTile(
          title: const Text('Message history'),
          subtitle: const Text('How long to keep sent and received messages.'),
          trailing: _dayDropdown(
            value: messages.messageHistoryDays,
            onChanged: messages.setMessageHistoryDays,
          ),
        ),

        // Clear actions
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Symbols.delete_sweep, size: 18),
                label: const Text('Clear packet log'),
                onPressed: () async {
                  await context.read<StationService>().clearPacketLog();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Packet log cleared')),
                    );
                  }
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Symbols.location_off, size: 18),
                label: const Text('Clear stations'),
                onPressed: () async {
                  await context.read<StationService>().clearStationHistory();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Station history cleared')),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
