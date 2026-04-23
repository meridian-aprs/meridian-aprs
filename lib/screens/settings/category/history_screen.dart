import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../services/message_service.dart';
import '../../../services/station_service.dart';
import '../advanced_mode_controller.dart';
import '../widgets/section_header.dart';

class HistorySettingsContent extends StatelessWidget {
  const HistorySettingsContent({super.key});

  static const _dayOptions = [7, 14, 30, 90, 180, 365, 0];

  static String _label(int days) => days == 0 ? 'Forever' : '$days days';

  static int _snap(int value) => _dayOptions.reduce(
    (a, b) => (a - value).abs() <= (b - value).abs() ? a : b,
  );

  static void _showPicker(
    BuildContext context, {
    required int currentValue,
    required ValueChanged<int> onChanged,
    required String title,
  }) {
    final snapped = _snap(currentValue);
    if (!kIsWeb && Platform.isIOS) {
      showCupertinoModalPopup<int>(
        context: context,
        builder: (_) => CupertinoActionSheet(
          title: Text(title),
          actions: _dayOptions
              .map(
                (d) => CupertinoActionSheetAction(
                  onPressed: () => Navigator.pop(context, d),
                  child: Text(_label(d)),
                ),
              )
              .toList(),
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ),
      ).then((v) {
        if (v != null) onChanged(v);
      });
    } else {
      showDialog<int>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(title),
          children: _dayOptions
              .map(
                (d) => SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx).pop(d),
                  child: Text(
                    _label(d),
                    style: d == snapped
                        ? TextStyle(
                            color: Theme.of(ctx).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          )
                        : null,
                  ),
                ),
              )
              .toList(),
        ),
      ).then((v) {
        if (v != null) onChanged(v);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final stations = context.watch<StationService>();
    final messages = context.watch<MessageService>();
    final advanced = context.watch<AdvancedModeController>();

    return ListView(
      children: [
        const SectionHeader('Retention'),
        ListTile(
          title: const Text('Packet log'),
          subtitle: const Text('How long to keep received packets.'),
          trailing: Text(_label(_snap(stations.packetHistoryDays))),
          onTap: () => _showPicker(
            context,
            currentValue: stations.packetHistoryDays,
            onChanged: stations.setPacketHistoryDays,
            title: 'Packet log',
          ),
        ),
        ListTile(
          title: const Text('Station history'),
          subtitle: const Text('How long to remember heard stations.'),
          trailing: Text(_label(_snap(stations.stationHistoryDays))),
          onTap: () => _showPicker(
            context,
            currentValue: stations.stationHistoryDays,
            onChanged: stations.setStationHistoryDays,
            title: 'Station history',
          ),
        ),
        ListTile(
          title: const Text('Message history'),
          subtitle: const Text('How long to keep sent and received messages.'),
          trailing: Text(_label(_snap(messages.messageHistoryDays))),
          onTap: () => _showPicker(
            context,
            currentValue: messages.messageHistoryDays,
            onChanged: messages.setMessageHistoryDays,
            title: 'Message history',
          ),
        ),
        if (advanced.isEnabled) ...[
          const SectionHeader('Clear data'),
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
                        const SnackBar(
                          content: Text('Station history cleared'),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}
