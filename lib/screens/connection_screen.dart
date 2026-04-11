import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../core/connection/aprs_is_connection.dart';
import '../core/connection/ble_connection.dart';
import '../core/connection/connection_registry.dart';
import '../core/connection/serial_connection.dart';
import '../core/packet/aprs_packet.dart' show AprsPacket, PacketSource;
import '../core/transport/tnc_config.dart';
import '../core/transport/tnc_preset.dart';
import '../services/background_service_manager.dart';
import '../services/station_service.dart';
import '../services/station_settings_service.dart';
import '../theme/meridian_colors.dart';
import '../ui/widgets/ble_scanner_sheet.dart';
import '../ui/widgets/meridian_status_pill.dart';

/// Full-screen destination for managing all transport connections.
///
/// Shows active connection cards at the top when ≥1 transport is connected,
/// followed by a platform-adaptive segmented control built from
/// [ConnectionRegistry.available] and the corresponding connection form.
///
/// All services are read from the [Provider] tree — no constructor params.
class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  // Segmented control selection index into [ConnectionRegistry.available].
  int _tab = 0;

  // Packet counters keyed by connection ID.
  final Map<String, int> _packetCountById = {};

  StreamSubscription<AprsPacket>? _packetSub;

  // Serial TNC form state (desktop only).
  late TncPreset _selectedPreset;
  late List<String> _availablePorts;
  String? _selectedPort;

  @override
  void initState() {
    super.initState();
    _selectedPreset = TncPreset.mobilinkdTnc4;
    _availablePorts = [];

    final registry = context.read<ConnectionRegistry>();
    final stationService = context.read<StationService>();

    // Restore serial config from the registry's SerialConnection (if present).
    final serialConn = registry.all.whereType<SerialConnection>().firstOrNull;
    if (serialConn != null) {
      final activeConfig = serialConn.activeConfig;
      if (activeConfig?.presetId != null) {
        _selectedPreset = TncPreset.all.firstWhere(
          (p) => p.id == activeConfig!.presetId,
          orElse: () => TncPreset.mobilinkdTnc4,
        );
      }
      _refreshSerialPorts(initial: activeConfig?.port);
    }

    // Seed packet counters from the rolling buffer.
    for (final p in stationService.recentPackets) {
      final key = switch (p.transportSource) {
        PacketSource.tnc => 'ble_tnc',
        PacketSource.bleTnc => 'ble_tnc',
        PacketSource.serialTnc => 'serial_tnc',
        PacketSource.aprsIs => 'aprs_is',
      };
      _packetCountById[key] = (_packetCountById[key] ?? 0) + 1;
    }

    // Keep counters live as new packets arrive.
    _packetSub = stationService.packetStream.listen((p) {
      if (!mounted) return;
      setState(() {
        final key = switch (p.transportSource) {
          PacketSource.tnc => 'ble_tnc',
          PacketSource.bleTnc => 'ble_tnc',
          PacketSource.serialTnc => 'serial_tnc',
          PacketSource.aprsIs => 'aprs_is',
        };
        _packetCountById[key] = (_packetCountById[key] ?? 0) + 1;
      });
    });
  }

  @override
  void dispose() {
    _packetSub?.cancel();
    super.dispose();
  }

  void _refreshSerialPorts({String? initial}) {
    final registry = context.read<ConnectionRegistry>();
    final serialConn = registry.all.whereType<SerialConnection>().firstOrNull;
    final ports = serialConn?.availablePorts() ?? <String>[];
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

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final registry = context.watch<ConnectionRegistry>();
    final available = registry.available;

    // Clamp tab index to remain valid if registry changes.
    if (_tab >= available.length && available.isNotEmpty) {
      _tab = available.length - 1;
    }

    final activeConnections = registry.all.where((c) {
      return c.status == ConnectionStatus.connected ||
          c.status == ConnectionStatus.reconnecting ||
          c.status == ConnectionStatus.waitingForDevice;
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Connection')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Background service reconnecting banner (Android) ──────────
            if (!kIsWeb && Platform.isAndroid)
              Consumer<BackgroundServiceManager>(
                builder: (context, bsm, _) {
                  if (bsm.state != BackgroundServiceState.reconnecting) {
                    return const SizedBox.shrink();
                  }
                  return ColoredBox(
                    color: MeridianColors.warning.withValues(alpha: 0.15),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator.adaptive(
                              strokeWidth: 2,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text('Reconnecting in background\u2026'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

            // ── Active connections ────────────────────────────────────────
            if (activeConnections.isNotEmpty) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _SectionLabel('Active connections'),
              ),
              ...activeConnections.map(
                (conn) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: _ActiveConnectionCard(
                    connection: conn,
                    packetCount: _packetCountById[conn.id] ?? 0,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Divider(height: 1),
            ],

            // ── Segmented control + tabs ──────────────────────────────────
            const SizedBox(height: 20),
            if (available.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildSegmentedControl(available),
              ),
            const SizedBox(height: 20),
            if (available.isNotEmpty)
              _buildTabContent(available[_tab.clamp(0, available.length - 1)]),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Segmented control
  // ---------------------------------------------------------------------------

  Widget _buildSegmentedControl(List<MeridianConnection> available) {
    if (!kIsWeb && Platform.isIOS) {
      final children = <int, Widget>{
        for (var i = 0; i < available.length; i++)
          i: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(available[i].displayName),
          ),
      };
      return CupertinoSlidingSegmentedControl<int>(
        groupValue: _tab,
        children: children,
        onValueChanged: (v) => setState(() => _tab = v ?? 0),
      );
    }

    return SegmentedButton<int>(
      segments: [
        for (var i = 0; i < available.length; i++)
          ButtonSegment(value: i, label: Text(available[i].displayName)),
      ],
      selected: {_tab.clamp(0, available.length - 1)},
      onSelectionChanged: (s) => setState(() => _tab = s.first),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab content dispatch
  // ---------------------------------------------------------------------------

  Widget _buildTabContent(MeridianConnection conn) {
    if (conn is AprsIsConnection) return _buildAprsTab(conn);
    if (conn is BleConnection) return _buildBleTab(conn);
    if (conn is SerialConnection) return _buildSerialTab(conn);
    // Fallback for test fakes or unknown connection types.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(conn.displayName),
    );
  }

  // ── APRS-IS tab ────────────────────────────────────────────────────────────

  Widget _buildAprsTab(AprsIsConnection conn) {
    final theme = Theme.of(context);
    final settings = context.read<StationSettingsService>();
    final isConnected = conn.status == ConnectionStatus.connected;
    final isConnecting = conn.status == ConnectionStatus.connecting;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(label: 'Server', value: 'rotate.aprs2.net'),
                  const SizedBox(height: 8),
                  _InfoRow(label: 'Port', value: '14580'),
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: 'Callsign',
                    value: settings.callsign.isEmpty
                        ? '— not set'
                        : settings.fullAddress,
                    valueColor: settings.callsign.isEmpty
                        ? theme.colorScheme.error
                        : null,
                  ),
                  if (settings.callsign.isEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Set your callsign in Settings before connecting.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    'Edit server in Settings (coming in a future update).',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (isConnected)
            Text(
              'Connected — disconnect from the card above.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: isConnecting ? null : conn.connect,
                child: Text(
                  isConnecting ? 'Connecting\u2026' : 'Connect APRS-IS',
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── BLE TNC tab ────────────────────────────────────────────────────────────

  Widget _buildBleTab(BleConnection conn) {
    final isSessionActive =
        conn.status == ConnectionStatus.connected ||
        conn.status == ConnectionStatus.reconnecting ||
        conn.status == ConnectionStatus.waitingForDevice;

    if (isSessionActive) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          'Connected — disconnect from the card above.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: BleScannerSheet(
        bleConnection: conn,
        showDragHandle: false,
        onBack: () {},
        showBackButton: false,
      ),
    );
  }

  // ── Serial TNC tab ─────────────────────────────────────────────────────────

  Widget _buildSerialTab(SerialConnection conn) {
    final theme = Theme.of(context);
    final isConnected = conn.status == ConnectionStatus.connected;
    final isConnecting = conn.status == ConnectionStatus.connecting;
    final errorMessage = conn.lastErrorMessage;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Preset dropdown.
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Preset',
                          style: theme.textTheme.bodyMedium,
                        ),
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

                  // Port dropdown with refresh.
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
                        icon: const Icon(Symbols.refresh),
                        tooltip: 'Refresh port list',
                        onPressed: isConnecting
                            ? null
                            : () => setState(
                                () =>
                                    _refreshSerialPorts(initial: _selectedPort),
                              ),
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
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (isConnected)
            Text(
              'Connected — disconnect from the card above.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else ...[
            if (_availablePorts.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'No serial devices found. Connect a TNC via USB.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (_selectedPort == null || isConnecting)
                    ? null
                    : () async {
                        final config = TncConfig.fromPreset(
                          _selectedPreset,
                          port: _selectedPort!,
                        );
                        await conn.connectWithConfig(config);
                      },
                child: Text(isConnecting ? 'Connecting\u2026' : 'Connect'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// Active connection card (unified)
// =============================================================================

class _ActiveConnectionCard extends StatelessWidget {
  const _ActiveConnectionCard({
    required this.connection,
    required this.packetCount,
  });

  final MeridianConnection connection;
  final int packetCount;

  static IconData _iconFor(ConnectionType type) => switch (type) {
    ConnectionType.aprsIs => Symbols.wifi,
    ConnectionType.bleTnc => Symbols.bluetooth,
    ConnectionType.serialTnc => Symbols.usb,
  };

  static String _subtitleFor(MeridianConnection conn) {
    if (conn.type == ConnectionType.aprsIs) return 'rotate.aprs2.net:14580';
    if (conn is SerialConnection) {
      return conn.activeConfig?.port ?? 'Serial TNC';
    }
    if (conn.type == ConnectionType.bleTnc) return 'BLE TNC';
    return conn.displayName;
  }

  static String _formatCount(int n) => '$n packet${n == 1 ? '' : 's'} received';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conn = connection;
    final status = conn.status;
    final displayStatus = status == ConnectionStatus.connected
        ? status
        : ConnectionStatus.connecting;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_iconFor(conn.type), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    conn.displayName,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                MeridianStatusPill(
                  status: displayStatus,
                  label: status == ConnectionStatus.connected
                      ? 'Connected'
                      : 'Reconnecting\u2026',
                ),
                if (conn.beaconingEnabled) ...[
                  const SizedBox(width: 8),
                  _TxBadge(),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _subtitleFor(conn),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _formatCount(packetCount),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SwitchListTile.adaptive(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Beacon'),
              value: conn.beaconingEnabled,
              onChanged: (v) => conn.setBeaconingEnabled(v),
            ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: MeridianColors.danger,
                  side: const BorderSide(color: MeridianColors.danger),
                ),
                onPressed: conn.disconnect,
                child: const Text('Disconnect'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Small shared widgets
// =============================================================================

class _TxBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: MeridianColors.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'TX',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: MeridianColors.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: valueColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}
