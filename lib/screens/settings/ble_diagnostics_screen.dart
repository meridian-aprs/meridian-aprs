import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/transport/ble_diagnostics.dart';

/// Live view of the BLE diagnostics ring buffer.
///
/// Surfaced under Settings → Advanced. Hidden unless Advanced User Mode is on.
/// The user copies the log to clipboard after a drive test so we can diagnose
/// background BLE drops with real timestamps and reasons.
class BleDiagnosticsScreen extends StatefulWidget {
  const BleDiagnosticsScreen({super.key});

  @override
  State<BleDiagnosticsScreen> createState() => _BleDiagnosticsScreenState();
}

class _BleDiagnosticsScreenState extends State<BleDiagnosticsScreen> {
  late final BleDiagnostics _diag;

  @override
  void initState() {
    super.initState();
    _diag = BleDiagnostics.I;
    _diag.addListener(_onDiagChanged);
  }

  @override
  void dispose() {
    _diag.removeListener(_onDiagChanged);
    super.dispose();
  }

  void _onDiagChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _copyToClipboard() async {
    final events = _diag.events;
    final buffer = StringBuffer();
    buffer.writeln('Meridian APRS BLE diagnostics');
    buffer.writeln('Captured: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Events: ${events.length}');
    buffer.writeln('---');
    for (final e in events) {
      buffer.writeln(e.formatHuman());
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied ${events.length} events to clipboard')),
    );
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear diagnostics?'),
        content: const Text(
          'This removes all BLE diagnostic events. The log will rebuild as new '
          'events occur.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _diag.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = _diag.events;
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Diagnostics'),
        actions: [
          IconButton(
            tooltip: 'Copy log',
            onPressed: events.isEmpty ? null : _copyToClipboard,
            icon: const Icon(Symbols.content_copy),
          ),
          IconButton(
            tooltip: 'Clear log',
            onPressed: events.isEmpty ? null : _confirmClear,
            icon: const Icon(Symbols.delete_sweep),
          ),
        ],
      ),
      body: events.isEmpty
          ? const _EmptyState()
          : ListView.builder(
              reverse: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: events.length,
              itemBuilder: (context, index) {
                // Newest at the top → reverse the index.
                final event = events[events.length - 1 - index];
                return _EventTile(event: event);
              },
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Symbols.bluetooth_searching,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No BLE events yet',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Connect a BLE TNC and use the app — connect/disconnect, '
              'reconnect attempts, and keepalive activity will appear here.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final BleEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _colorForKind(event.kind, theme);
    return ListTile(
      dense: true,
      leading: Icon(_iconForKind(event.kind), color: color, size: 20),
      title: Text(
        event.kind.name,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      subtitle: Text(
        '${_formatTime(event.timestamp)}'
        '${event.detail.isEmpty ? '' : '  ·  ${event.detail}'}',
        style: theme.textTheme.bodySmall?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  static String _formatTime(DateTime t) {
    final l = t.toLocal();
    final hh = l.hour.toString().padLeft(2, '0');
    final mm = l.minute.toString().padLeft(2, '0');
    final ss = l.second.toString().padLeft(2, '0');
    final ms = l.millisecond.toString().padLeft(3, '0');
    return '$hh:$mm:$ss.$ms';
  }

  static IconData _iconForKind(BleEventKind kind) {
    switch (kind) {
      case BleEventKind.connectStart:
      case BleEventKind.connectSuccess:
      case BleEventKind.sessionConnected:
        return Symbols.bluetooth_connected;
      case BleEventKind.connectFailed:
      case BleEventKind.disconnectUnexpected:
      case BleEventKind.disconnectKeepaliveFailed:
        return Symbols.bluetooth_disabled;
      case BleEventKind.disconnectUser:
      case BleEventKind.disconnectInternal:
        return Symbols.link_off;
      case BleEventKind.bleStateChanged:
        return Symbols.swap_horiz;
      case BleEventKind.serviceDiscoveryRetry:
        return Symbols.refresh;
      case BleEventKind.connectionPriorityRequested:
      case BleEventKind.connectionPriorityFailed:
        return Symbols.speed;
      case BleEventKind.keepaliveSent:
        return Symbols.favorite;
      case BleEventKind.keepaliveRetried:
        return Symbols.autorenew;
      case BleEventKind.keepaliveFailed:
        return Symbols.heart_broken;
      case BleEventKind.reconnectScheduled:
      case BleEventKind.reconnectAttempt:
        return Symbols.replay;
      case BleEventKind.waitingPhase:
        return Symbols.hourglass_empty;
      case BleEventKind.note:
        return Symbols.sticky_note_2;
    }
  }

  static Color _colorForKind(BleEventKind kind, ThemeData theme) {
    final cs = theme.colorScheme;
    switch (kind) {
      case BleEventKind.connectSuccess:
      case BleEventKind.sessionConnected:
        return cs.primary;
      case BleEventKind.connectFailed:
      case BleEventKind.disconnectUnexpected:
      case BleEventKind.disconnectKeepaliveFailed:
      case BleEventKind.keepaliveFailed:
        return cs.error;
      case BleEventKind.reconnectScheduled:
      case BleEventKind.reconnectAttempt:
      case BleEventKind.waitingPhase:
      case BleEventKind.serviceDiscoveryRetry:
        return cs.tertiary;
      default:
        return cs.onSurface;
    }
  }
}
