import 'package:flutter/material.dart';

import '../../core/packet/aprs_packet.dart';
import 'aprs_symbol_widget.dart';

/// Shows a modal bottom sheet with the full decoded detail of an [AprsPacket].
///
/// Usage:
/// ```dart
/// showPacketDetailSheet(context, packet);
/// ```
void showPacketDetailSheet(BuildContext context, AprsPacket packet) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => PacketDetailSheet(packet: packet),
  );
}

class PacketDetailSheet extends StatelessWidget {
  const PacketDetailSheet({super.key, required this.packet});

  final AprsPacket packet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    final fields = _decodedFields(packet);
    final symbol = _symbolFor(packet);

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (_, controller) => Column(
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 32,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header row: symbol + callsign + close button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                children: [
                  if (symbol case (final st, final sc)) ...[
                    AprsSymbolWidget(symbolTable: st, symbolCode: sc, size: 24),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      packet.source,
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  // Raw packet line
                  _SectionLabel(label: 'Raw packet', colorScheme: colorScheme),
                  const SizedBox(height: 4),
                  SelectableText(
                    packet.rawLine,
                    style: textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Decoded fields
                  _SectionLabel(
                    label: 'Decoded fields',
                    colorScheme: colorScheme,
                  ),
                  const SizedBox(height: 4),
                  ...fields.entries.map(
                    (e) =>
                        _FieldRow(label: e.key, value: e.value, theme: theme),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Returns (symbolTable, symbolCode) for packet types that carry a symbol,
  /// or null for those that do not.
  (String, String)? _symbolFor(AprsPacket p) {
    return switch (p) {
      PositionPacket() => (p.symbolTable, p.symbolCode),
      WeatherPacket() => (p.symbolTable, p.symbolCode),
      ObjectPacket() => (p.symbolTable, p.symbolCode),
      ItemPacket() => (p.symbolTable, p.symbolCode),
      MicEPacket() => (p.symbolTable, p.symbolCode),
      _ => null,
    };
  }

  /// Builds an ordered map of label → value for all meaningful decoded fields.
  Map<String, String> _decodedFields(AprsPacket p) {
    final m = <String, String>{};

    // Common header fields
    m['Source'] = p.source;
    m['Destination'] = p.destination;
    if (p.path.isNotEmpty) m['Path'] = p.path.join(', ');
    m['Received'] = p.receivedAt
        .toUtc()
        .toString()
        .replaceFirst('.000', '')
        .replaceAll('T', ' ');

    switch (p) {
      case PositionPacket():
        m['Type'] = 'Position';
        m['Latitude'] = _formatLat(p.lat);
        m['Longitude'] = _formatLon(p.lon);
        m['Symbol table'] = p.symbolTable;
        m['Symbol code'] = p.symbolCode;
        if (p.course != null) m['Course'] = '${p.course}\u00b0';
        if (p.speed != null) m['Speed'] = '${p.speed!.toStringAsFixed(1)} kt';
        if (p.altitude != null) {
          m['Altitude'] = '${p.altitude!.toStringAsFixed(0)} m';
        }
        m['Messaging'] = p.hasMessaging ? 'Yes' : 'No';
        if (p.device != null) m['Device'] = p.device!;
        if (p.comment.isNotEmpty) m['Comment'] = p.comment;
        if (p.timestamp != null) m['Packet time'] = p.timestamp.toString();

      case MessagePacket():
        m['Type'] = 'Message';
        m['Addressee'] = p.addressee;
        m['Message'] = p.message;
        if (p.messageId != null) m['Message ID'] = p.messageId!;

      case WeatherPacket():
        m['Type'] = 'Weather';
        if (p.lat != null) m['Latitude'] = _formatLat(p.lat!);
        if (p.lon != null) m['Longitude'] = _formatLon(p.lon!);
        if (p.temperature != null) {
          final c = (p.temperature! - 32) * 5 / 9;
          m['Temperature'] =
              '${p.temperature!.toStringAsFixed(1)} \u00b0F (${c.toStringAsFixed(1)} \u00b0C)';
        }
        if (p.humidity != null) m['Humidity'] = '${p.humidity}%';
        if (p.pressure != null) {
          m['Pressure'] = '${p.pressure!.toStringAsFixed(1)} hPa';
        }
        if (p.windSpeed != null) {
          m['Wind speed'] = '${p.windSpeed!.toStringAsFixed(1)} mph';
        }
        if (p.windDirection != null) {
          m['Wind direction'] = '${p.windDirection}\u00b0';
        }
        if (p.windGust != null) {
          m['Wind gust'] = '${p.windGust!.toStringAsFixed(1)} mph';
        }
        if (p.rainfall1h != null) {
          m['Rainfall 1h'] = '${(p.rainfall1h! / 100).toStringAsFixed(2)} in';
        }
        if (p.rainfall24h != null) {
          m['Rainfall 24h'] = '${(p.rainfall24h! / 100).toStringAsFixed(2)} in';
        }

      case ObjectPacket():
        m['Type'] = 'Object';
        m['Object name'] = p.objectName;
        m['Latitude'] = _formatLat(p.lat);
        m['Longitude'] = _formatLon(p.lon);
        m['Symbol table'] = p.symbolTable;
        m['Symbol code'] = p.symbolCode;
        m['Alive'] = p.isAlive ? 'Yes' : 'No (killed)';
        if (p.device != null) m['Device'] = p.device!;
        if (p.comment.isNotEmpty) m['Comment'] = p.comment;

      case ItemPacket():
        m['Type'] = 'Item';
        m['Item name'] = p.itemName;
        m['Latitude'] = _formatLat(p.lat);
        m['Longitude'] = _formatLon(p.lon);
        m['Symbol table'] = p.symbolTable;
        m['Symbol code'] = p.symbolCode;
        m['Alive'] = p.isAlive ? 'Yes' : 'No (killed)';
        if (p.device != null) m['Device'] = p.device!;
        if (p.comment.isNotEmpty) m['Comment'] = p.comment;

      case StatusPacket():
        m['Type'] = 'Status';
        m['Status'] = p.status;
        if (p.timestamp != null) m['Packet time'] = p.timestamp.toString();

      case MicEPacket():
        m['Type'] = 'Mic-E';
        m['Latitude'] = _formatLat(p.lat);
        m['Longitude'] = _formatLon(p.lon);
        m['Mic-E status'] = p.micEMessage;
        m['Symbol table'] = p.symbolTable;
        m['Symbol code'] = p.symbolCode;
        if (p.course != null) m['Course'] = '${p.course}\u00b0';
        if (p.speed != null) m['Speed'] = '${p.speed!.toStringAsFixed(1)} kt';
        if (p.altitude != null) {
          m['Altitude'] = '${p.altitude!.toStringAsFixed(0)} m';
        }
        if (p.device != null) m['Device'] = p.device!;
        if (p.comment.isNotEmpty) m['Comment'] = p.comment;

      case UnknownPacket():
        m['Type'] = 'Unknown';
        m['Reason'] = p.reason;
        if (p.rawInfo.isNotEmpty) m['Raw info'] = p.rawInfo;
    }

    return m;
  }
}

String _formatLat(double lat) {
  final dir = lat >= 0 ? 'N' : 'S';
  return '${lat.abs().toStringAsFixed(6)}\u00b0 $dir';
}

String _formatLon(double lon) {
  final dir = lon >= 0 ? 'E' : 'W';
  return '${lon.abs().toStringAsFixed(6)}\u00b0 $dir';
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.colorScheme});

  final String label;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: colorScheme.primary,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    required this.value,
    required this.theme,
  });

  final String label;
  final String value;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
