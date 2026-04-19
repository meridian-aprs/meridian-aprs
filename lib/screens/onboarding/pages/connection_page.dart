import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../core/connection/aprs_is_connection.dart';
import '../../../core/connection/ble_connection.dart';
import '../../../core/connection/connection_registry.dart';
import '../../../core/connection/serial_connection.dart';
import '../../../ui/widgets/ble_scanner_sheet.dart';
import '../../../ui/widgets/serial_connection_form.dart';

/// Onboarding step 6 — pick an APRS connection method.
class ConnectionPage extends StatefulWidget {
  const ConnectionPage({
    super.key,
    required this.onNext,
    required this.onBack,
    required this.onConnectionResult,
  });

  /// Advance to the next onboarding step.
  final VoidCallback onNext;

  /// Go back to the previous step.
  final VoidCallback onBack;

  /// Called when the user finishes (or skips) connection setup.
  /// [configured] is true if a connection was successfully established.
  final void Function(bool configured) onConnectionResult;

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  bool _connecting = false;
  String? _error;
  bool _serialExpanded = false;

  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  bool get _isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  Future<void> _connectAprsIs() async {
    setState(() {
      _connecting = true;
      _error = null;
    });

    final registry = context.read<ConnectionRegistry>();
    final aprsIsConn = registry.byId('aprs_is');
    if (aprsIsConn is! AprsIsConnection) {
      widget.onConnectionResult(false);
      widget.onNext();
      return;
    }

    try {
      await aprsIsConn.connect();
      // Fire-and-forget: connection result is optimistic. The status pill on
      // the map will reflect the actual state. This keeps the onboarding flow
      // non-blocking.
      if (mounted) {
        widget.onConnectionResult(true);
        widget.onNext();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error =
              'Could not connect to APRS-IS. Check your network and try '
              'again, or continue to the map and connect later.';
        });
      }
    }
  }

  void _openBleScanner() {
    final registry = context.read<ConnectionRegistry>();
    final bleConn = registry.byId('ble_tnc');
    if (bleConn is! BleConnection) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => BleScannerSheet(
          bleConnection: bleConn,
          showDragHandle: true,
          // onBack is used only for the visual back button; navigation is
          // handled in the .then() callback below so we avoid double-advance.
          onBack: () => Navigator.of(context).pop(),
          showBackButton: true,
        ),
      ),
    ).then((_) {
      // Advance only once, after the sheet has fully closed.
      if (mounted && bleConn.isConnected) {
        widget.onConnectionResult(true);
        widget.onNext();
      }
    });
  }

  void _skipToLater() {
    widget.onConnectionResult(false);
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
              'Connect to APRS',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose how Meridian connects to the APRS network.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),

            // Error banner
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Symbols.error_outline,
                          color: colorScheme.onErrorContainer,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _skipToLater,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        foregroundColor: colorScheme.onErrorContainer,
                      ),
                      child: const Text('Continue anyway'),
                    ),
                  ],
                ),
              ),
            ],

            // APRS-IS tile (all platforms)
            _ConnectionTile(
              icon: Icons.wifi,
              title: 'APRS-IS',
              subtitle: 'Connect via internet. No hardware required.',
              loading: _connecting,
              onTap: _connecting ? null : _connectAprsIs,
            ),

            // BLE TNC (mobile only)
            if (_isMobile) ...[
              const SizedBox(height: 12),
              _ConnectionTile(
                icon: Icons.bluetooth,
                title: 'BLE TNC',
                subtitle: 'Connect wirelessly to a TNC.',
                onTap: _openBleScanner,
              ),
            ],

            // USB Serial (desktop only) — expandable inline form.
            if (_isDesktop) ...[
              const SizedBox(height: 12),
              _ConnectionTile(
                icon: Icons.usb,
                title: 'USB Serial TNC',
                subtitle: 'Connect via USB cable.',
                selected: _serialExpanded,
                onTap: () => setState(() => _serialExpanded = !_serialExpanded),
              ),
              if (_serialExpanded)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Builder(
                    builder: (ctx) {
                      final registry = ctx.read<ConnectionRegistry>();
                      final serialConn = registry.byId('serial_tnc');
                      if (serialConn is! SerialConnection) {
                        return const SizedBox.shrink();
                      }
                      return SerialConnectionForm(
                        connection: serialConn,
                        showConnectedHint: false,
                        onConnected: () {
                          widget.onConnectionResult(true);
                          widget.onNext();
                        },
                      );
                    },
                  ),
                ),
            ],

            const SizedBox(height: 12),
            _ConnectionTile(
              icon: Icons.arrow_forward,
              title: 'Set up later',
              subtitle: "I'll connect from the app.",
              onTap: _skipToLater,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionTile extends StatelessWidget {
  const _ConnectionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.loading = false,
    this.selected = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool loading;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? colorScheme.primary : colorScheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              loading
                  ? SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    )
                  : Icon(
                      icon,
                      size: 32,
                      color: onTap == null
                          ? colorScheme.onSurfaceVariant.withValues(alpha: 0.4)
                          : colorScheme.onSurfaceVariant,
                    ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: onTap == null
                            ? colorScheme.onSurface.withValues(alpha: 0.4)
                            : colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
