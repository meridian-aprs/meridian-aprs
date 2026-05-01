import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:permission_handler/permission_handler.dart';
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

      // connect() returns once the TCP socket is up. The APRS-IS login is then
      // validated by the server — if the passcode is wrong or the server is
      // otherwise unhappy, it closes the socket within ~1s. Watch the status
      // stream briefly to catch that case.
      final stabilized = await _waitForStableStatus(
        aprsIsConn,
        const Duration(seconds: 2),
      );

      if (!mounted) return;
      if (stabilized) {
        widget.onConnectionResult(true);
        widget.onNext();
      } else {
        setState(() {
          _connecting = false;
          _error =
              'Connection was closed by APRS-IS. Check your callsign + '
              'passcode and try again, or continue and connect later.';
        });
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

  /// Waits up to [window] for [conn]'s status to remain [ConnectionStatus.connected].
  /// Returns false if it drops to disconnected (server-side login rejection).
  Future<bool> _waitForStableStatus(
    MeridianConnection conn,
    Duration window,
  ) async {
    if (conn.status != ConnectionStatus.connected) return false;
    final completer = Completer<bool>();
    late StreamSubscription<ConnectionStatus> sub;
    sub = conn.connectionState.listen((status) {
      if (status == ConnectionStatus.disconnected && !completer.isCompleted) {
        completer.complete(false);
      }
    });
    Timer(window, () {
      if (!completer.isCompleted) {
        completer.complete(conn.status == ConnectionStatus.connected);
      }
    });
    try {
      return await completer.future;
    } finally {
      await sub.cancel();
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
    ).then((_) async {
      if (!mounted) return;
      // BLE status can flicker briefly as the session stabilises — give it a
      // short window before reading final state so a transient "connecting"
      // doesn't mislead us into advancing as "not configured".
      final stable = await _waitForStableStatus(
        bleConn,
        const Duration(milliseconds: 600),
      );
      if (!mounted) return;
      if (stable) {
        // The user has just committed to BLE. Prompt for the battery-opt
        // exemption now while the choice is fresh — without it the link will
        // drop and stay dropped under Doze. Non-blocking: a denial does not
        // prevent onboarding from advancing.
        await _maybeRequestBatteryOptExemption();
        if (!mounted) return;
        widget.onConnectionResult(true);
        widget.onNext();
      }
    });
  }

  /// Ensures the user is offered the ignore-battery-optimization grant when
  /// completing BLE-TNC onboarding on Android. No-op on other platforms or
  /// when the exemption is already in place.
  Future<void> _maybeRequestBatteryOptExemption() async {
    if (kIsWeb || !Platform.isAndroid) return;
    final status = await Permission.ignoreBatteryOptimizations.status;
    if (status.isGranted) return;
    await Permission.ignoreBatteryOptimizations.request();
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
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: _connectAprsIs,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Retry'),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            foregroundColor: colorScheme.onErrorContainer,
                          ),
                        ),
                        const SizedBox(width: 4),
                        TextButton(
                          onPressed: _skipToLater,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            foregroundColor: colorScheme.onErrorContainer,
                          ),
                          child: const Text('Continue anyway'),
                        ),
                      ],
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
