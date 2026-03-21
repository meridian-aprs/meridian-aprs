import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../core/packet/aprs_packet.dart' show AprsPacket, PacketSource;
import '../../core/transport/aprs_transport.dart' show ConnectionStatus;
import '../../core/transport/tnc_config.dart';
import '../../core/transport/tnc_preset.dart';
import '../../services/station_service.dart';
import '../../services/tnc_service.dart';
import 'meridian_status_pill.dart';

/// Bottom sheet content for managing APRS-IS and TNC connection settings.
///
/// Shows two sections:
///  - APRS-IS: read-only status pill reflecting the current APRS-IS connection.
///  - TNC: preset/port picker, connect/disconnect button, and error display.
///    Only enabled on Linux, macOS, and Windows; all other platforms show a
///    dimmed informational card instead.
class ConnectionSheet extends StatefulWidget {
  const ConnectionSheet({
    super.key,
    required this.stationService,
    required this.tncService,
  });

  final StationService stationService;
  final TncService tncService;

  @override
  State<ConnectionSheet> createState() => _ConnectionSheetState();
}

class _ConnectionSheetState extends State<ConnectionSheet> {
  late TncPreset _selectedPreset;
  late List<String> _availablePorts;
  String? _selectedPort;
  StreamSubscription<ConnectionStatus>? _tncSub;
  StreamSubscription<ConnectionStatus>? _aprsSub;
  StreamSubscription<AprsPacket>? _packetSub;
  int _aprsIsCount = 0;
  int _tncCount = 0;

  static bool get _isTncPlatform =>
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  @override
  void initState() {
    super.initState();

    // Initialise preset from persisted config or default to Mobilinkd TNC4.
    final activeConfig = widget.tncService.activeConfig;
    if (activeConfig?.presetId != null) {
      _selectedPreset = TncPreset.all.firstWhere(
        (p) => p.id == activeConfig!.presetId,
        orElse: () => TncPreset.mobilinkdTnc4,
      );
    } else {
      _selectedPreset = TncPreset.mobilinkdTnc4;
    }

    // Refresh available ports and seed selected port.
    _refreshPorts(initial: activeConfig?.port);

    // Subscribe to TNC connection state to rebuild on changes.
    _tncSub = widget.tncService.connectionState.listen((status) {
      if (mounted) setState(() {});
    });

    // Subscribe to APRS-IS connection state to rebuild on changes.
    _aprsSub = widget.stationService.connectionState.listen((status) {
      if (mounted) setState(() {});
    });

    // Seed packet counters from the rolling buffer.
    for (final p in widget.stationService.recentPackets) {
      if (p.transportSource == PacketSource.tnc) {
        _tncCount++;
      } else {
        _aprsIsCount++;
      }
    }

    // Keep counters live as new packets arrive.
    _packetSub = widget.stationService.packetStream.listen((p) {
      if (!mounted) return;
      setState(() {
        if (p.transportSource == PacketSource.tnc) {
          _tncCount++;
        } else {
          _aprsIsCount++;
        }
      });
    });
  }

  @override
  void dispose() {
    _tncSub?.cancel();
    _aprsSub?.cancel();
    _packetSub?.cancel();
    super.dispose();
  }

  void _refreshPorts({String? initial}) {
    final ports = _isTncPlatform ? widget.tncService.availablePorts() : [];
    _availablePorts = List<String>.from(ports);
    if (_availablePorts.isNotEmpty) {
      if (initial != null && _availablePorts.contains(initial)) {
        _selectedPort = initial;
      } else {
        _selectedPort = _availablePorts.first;
      }
    } else {
      _selectedPort = null;
    }
  }

  Future<void> _onConnectTap() async {
    if (_selectedPort == null) return;
    final config = TncConfig.fromPreset(_selectedPreset, port: _selectedPort!);
    await widget.tncService.connect(config);
  }

  Future<void> _onDisconnectTap() async {
    await widget.tncService.disconnect();
  }

  Future<void> _onAprsConnectTap() async {
    await widget.stationService.connectAprsIs();
  }

  Future<void> _onAprsDisconnectTap() async {
    await widget.stationService.disconnectAprsIs();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tncStatus = widget.tncService.currentStatus;
    final aprsStatus = widget.stationService.currentConnectionStatus;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── APRS-IS section ─────────────────────────────────────────────
          _SectionHeader('APRS-IS'),
          _buildAprsCard(theme, aprsStatus),
          const SizedBox(height: 20),

          // ── TNC section ──────────────────────────────────────────────────
          _SectionHeader('TNC'),
          if (!_isTncPlatform)
            _TncUnavailableCard()
          else
            _buildTncCard(theme, tncStatus),
        ],
      ),
    );
  }

  Widget _buildAprsCard(ThemeData theme, ConnectionStatus aprsStatus) {
    final isConnected = aprsStatus == ConnectionStatus.connected;
    final isConnecting = aprsStatus == ConnectionStatus.connecting;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Internet gateway connection',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                MeridianStatusPill(label: 'APRS-IS', status: aprsStatus),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$_aprsIsCount packets received',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: isConnected
                  ? OutlinedButton(
                      onPressed: _onAprsDisconnectTap,
                      child: const Text('Disconnect'),
                    )
                  : FilledButton(
                      onPressed: isConnecting ? null : _onAprsConnectTap,
                      child: Text(
                        isConnecting ? 'Connecting\u2026' : 'Connect',
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTncCard(ThemeData theme, ConnectionStatus tncStatus) {
    final isConnected = tncStatus == ConnectionStatus.connected;
    final isConnecting = tncStatus == ConnectionStatus.connecting;
    final errorMessage = widget.tncService.lastErrorMessage;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status pill row.
            Row(
              children: [
                Expanded(
                  child: Text(
                    'USB serial TNC',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                MeridianStatusPill(label: 'TNC', status: tncStatus),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$_tncCount packets received',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),

            // Preset dropdown.
            Row(
              children: [
                Expanded(
                  child: Text('Preset', style: theme.textTheme.bodyMedium),
                ),
                DropdownButton<TncPreset>(
                  value: _selectedPreset,
                  items: TncPreset.all.map((preset) {
                    return DropdownMenuItem<TncPreset>(
                      value: preset,
                      child: Text(preset.displayName),
                    );
                  }).toList(),
                  onChanged: isConnecting
                      ? null
                      : (preset) {
                          if (preset != null) {
                            setState(() => _selectedPreset = preset);
                          }
                        },
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Port dropdown with refresh button.
            Row(
              children: [
                Expanded(
                  child: Text('Port', style: theme.textTheme.bodyMedium),
                ),
                DropdownButton<String>(
                  value: _selectedPort,
                  hint: const Text('No ports found'),
                  items: _availablePorts.isEmpty
                      ? [
                          const DropdownMenuItem<String>(
                            enabled: false,
                            child: Text('No ports found'),
                          ),
                        ]
                      : _availablePorts.map((port) {
                          return DropdownMenuItem<String>(
                            value: port,
                            child: Text(port),
                          );
                        }).toList(),
                  onChanged: isConnecting
                      ? null
                      : (port) {
                          if (port != null) {
                            setState(() => _selectedPort = port);
                          }
                        },
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh port list',
                  onPressed: isConnecting
                      ? null
                      : () => setState(() {
                          _refreshPorts(initial: _selectedPort);
                        }),
                ),
              ],
            ),

            // Error message (if any).
            if (errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                errorMessage,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Connect / Disconnect button.
            SizedBox(
              width: double.infinity,
              child: isConnected
                  ? OutlinedButton(
                      onPressed: _onDisconnectTap,
                      child: const Text('Disconnect'),
                    )
                  : FilledButton(
                      onPressed: (_selectedPort == null || isConnecting)
                          ? null
                          : _onConnectTap,
                      child: Text(isConnecting ? 'Connecting…' : 'Connect'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TncUnavailableCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.5,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.usb, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'TNC is available on Linux, macOS, and Windows.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
