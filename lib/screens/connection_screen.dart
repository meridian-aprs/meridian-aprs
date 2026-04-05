import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../core/packet/aprs_packet.dart' show AprsPacket, PacketSource;
import '../core/transport/tnc_config.dart';
import '../core/transport/tnc_preset.dart';
import '../services/background_service_manager.dart';
import '../services/station_service.dart';
import '../services/station_settings_service.dart';
import '../services/tnc_service.dart';
import '../services/tx_service.dart';
import '../theme/meridian_colors.dart';
import '../ui/widgets/ble_scanner_sheet.dart';
import '../ui/widgets/meridian_status_pill.dart';

/// Full-screen destination for managing all transport connections.
///
/// Shows active connection cards at the top when ≥1 transport is connected,
/// followed by a platform-adaptive segmented control (APRS-IS / BLE TNC /
/// Serial TNC) and the corresponding connection form.
///
/// All services are read from the [Provider] tree — no constructor params.
class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  // Segmented control selection: 0 = APRS-IS, 1 = BLE TNC, 2 = Serial TNC.
  int _tab = 0;

  // Packet counters — seeded from rolling buffer, incremented live.
  int _aprsIsCount = 0;
  int _tncCount = 0;

  StreamSubscription<ConnectionStatus>? _tncSub;
  StreamSubscription<ConnectionStatus>? _aprsSub;
  StreamSubscription<AprsPacket>? _packetSub;

  // Serial TNC form state (desktop only).
  late TncPreset _selectedPreset;
  late List<String> _availablePorts;
  String? _selectedPort;
  int _baudRate = 9600;

  static bool get _isSerialPlatform =>
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  static bool get _isBlePlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static const _baudRates = [
    1200,
    2400,
    4800,
    9600,
    19200,
    38400,
    57600,
    115200,
  ];

  @override
  void initState() {
    super.initState();

    final stationService = context.read<StationService>();
    final tncService = context.read<TncService>();

    // Initialise preset from persisted config or default to Mobilinkd TNC4.
    final activeConfig = tncService.activeConfig;
    if (activeConfig?.presetId != null) {
      _selectedPreset = TncPreset.all.firstWhere(
        (p) => p.id == activeConfig!.presetId,
        orElse: () => TncPreset.mobilinkdTnc4,
      );
    } else {
      _selectedPreset = TncPreset.mobilinkdTnc4;
    }
    _refreshPorts(initial: activeConfig?.port);

    // Select initial tab to match the active transport.
    final tncStatus = tncService.currentStatus;
    if (tncStatus == ConnectionStatus.connected ||
        tncStatus == ConnectionStatus.connecting) {
      final type = tncService.activeTransportType;
      _tab = (type == TransportType.ble) ? 1 : (_isSerialPlatform ? 2 : 0);
    }

    // Subscribe to status streams for reactive rebuilds.
    _tncSub = tncService.connectionState.listen((_) {
      if (mounted) setState(() {});
    });
    _aprsSub = stationService.connectionState.listen((_) {
      if (mounted) setState(() {});
    });

    // Seed packet counters from the rolling buffer.
    for (final p in stationService.recentPackets) {
      if (p.transportSource == PacketSource.tnc) {
        _tncCount++;
      } else {
        _aprsIsCount++;
      }
    }

    // Keep counters live as new packets arrive.
    _packetSub = stationService.packetStream.listen((p) {
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
    final tncService = context.read<TncService>();
    final ports = _isSerialPlatform ? tncService.availablePorts() : <String>[];
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
    await context.read<TncService>().connect(config);
  }

  Future<void> _onDisconnectTncTap() async {
    await context.read<TncService>().disconnect();
  }

  Future<void> _onAprsConnectTap() async {
    await context.read<StationService>().connectAprsIs();
  }

  Future<void> _onAprsDisconnectTap() async {
    await context.read<StationService>().disconnectAprsIs();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final stationService = context.read<StationService>();
    final tncService = context.read<TncService>();

    final aprsStatus = stationService.currentConnectionStatus;
    final tncStatus = tncService.currentStatus;

    final aprsConnected = aprsStatus == ConnectionStatus.connected;
    final tncConnected = tncStatus == ConnectionStatus.connected;
    final anyConnected = aprsConnected || tncConnected;

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
            if (anyConnected) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _SectionLabel('Active connections'),
              ),
              if (aprsConnected) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _AprsActiveCard(
                    packetCount: _aprsIsCount,
                    onDisconnect: _onAprsDisconnectTap,
                  ),
                ),
              ],
              if (tncConnected) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _TncActiveCard(
                    tncService: tncService,
                    packetCount: _tncCount,
                    onDisconnect: _onDisconnectTncTap,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              const Divider(height: 1),
            ],

            // ── Segmented control + tabs ──────────────────────────────────
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildSegmentedControl(),
            ),
            const SizedBox(height: 20),
            _buildTabContent(aprsStatus, tncStatus),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Segmented control
  // ---------------------------------------------------------------------------

  Widget _buildSegmentedControl() {
    if (!kIsWeb && Platform.isIOS) {
      final children = <int, Widget>{
        0: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('APRS-IS'),
        ),
        1: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('BLE TNC'),
        ),
      };
      return CupertinoSlidingSegmentedControl<int>(
        groupValue: _tab,
        children: children,
        onValueChanged: (v) => setState(() => _tab = v ?? 0),
      );
    }

    final segments = <ButtonSegment<int>>[
      const ButtonSegment(value: 0, label: Text('APRS-IS')),
      if (_isBlePlatform) const ButtonSegment(value: 1, label: Text('BLE TNC')),
      if (_isSerialPlatform)
        const ButtonSegment(value: 2, label: Text('Serial TNC')),
    ];

    // If only one segment (e.g. web), just show the single label without the
    // segmented control chrome.
    if (segments.length == 1) {
      return const SizedBox.shrink();
    }

    return SegmentedButton<int>(
      segments: segments,
      selected: {_tab},
      onSelectionChanged: (s) => setState(() => _tab = s.first),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab content
  // ---------------------------------------------------------------------------

  Widget _buildTabContent(
    ConnectionStatus aprsStatus,
    ConnectionStatus tncStatus,
  ) {
    return switch (_tab) {
      1 when _isBlePlatform => _buildBleTab(tncStatus),
      2 when _isSerialPlatform => _buildSerialTab(tncStatus),
      _ => _buildAprsTab(aprsStatus),
    };
  }

  // ── APRS-IS tab ────────────────────────────────────────────────────────────

  Widget _buildAprsTab(ConnectionStatus aprsStatus) {
    final theme = Theme.of(context);
    final settings = context.read<StationSettingsService>();
    final isConnected = aprsStatus == ConnectionStatus.connected;
    final isConnecting = aprsStatus == ConnectionStatus.connecting;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Server info (read-only for v0.6 — server is set at app startup).
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
                onPressed: isConnecting ? null : _onAprsConnectTap,
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

  Widget _buildBleTab(ConnectionStatus tncStatus) {
    if (!_isBlePlatform) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: _TncUnavailableCard(
          message: 'BLE TNC is available on iOS and Android.',
        ),
      );
    }

    final isBleConnected =
        tncStatus == ConnectionStatus.connected &&
        context.read<TncService>().activeTransportType == TransportType.ble;

    if (isBleConnected) {
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

    final tncService = context.read<TncService>();
    // Lazy: only instantiate BleScannerSheet when this tab is active.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: BleScannerSheet(
        tncService: tncService,
        showDragHandle: false,
        // onBack must be non-null when embedded inline. BleScannerSheet calls
        // Navigator.pop() when onBack is null, which pops the root route and
        // leaves a black screen. A no-op here is correct: the _tncSub in
        // _ConnectionScreenState fires on connect and rebuilds the Active
        // Connections section automatically.
        onBack: () {},
        // Suppress the back arrow — this is embedded in a screen with its
        // own navigation; there is nothing to "go back" to.
        showBackButton: false,
      ),
    );
  }

  // ── Serial TNC tab ─────────────────────────────────────────────────────────

  Widget _buildSerialTab(ConnectionStatus tncStatus) {
    if (!_isSerialPlatform) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: _TncUnavailableCard(
          message: 'USB serial TNC is available on Linux, macOS, and Windows.',
        ),
      );
    }

    final theme = Theme.of(context);
    final isConnected =
        tncStatus == ConnectionStatus.connected &&
        context.read<TncService>().activeTransportType == TransportType.serial;
    final isConnecting = tncStatus == ConnectionStatus.connecting;
    final errorMessage = context.read<TncService>().lastErrorMessage;

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
                                () => _refreshPorts(initial: _selectedPort),
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Baud rate selector.
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Baud rate',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      DropdownButton<int>(
                        value: _baudRate,
                        items: _baudRates.map((baud) {
                          return DropdownMenuItem<int>(
                            value: baud,
                            child: Text(baud.toString()),
                          );
                        }).toList(),
                        onChanged: isConnecting
                            ? null
                            : (baud) {
                                if (baud != null) {
                                  setState(() => _baudRate = baud);
                                }
                              },
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
            // No ports found hint.
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
                    : _onConnectTap,
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
// Active connection cards
// =============================================================================

class _AprsActiveCard extends StatelessWidget {
  const _AprsActiveCard({
    required this.packetCount,
    required this.onDisconnect,
  });

  final int packetCount;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Symbols.wifi, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('APRS-IS', style: theme.textTheme.titleSmall),
                ),
                const MeridianStatusPill(
                  status: ConnectionStatus.connected,
                  label: 'Connected',
                ),
                const SizedBox(width: 8),
                Consumer<TxService>(
                  builder: (_, txSvc, _) {
                    if (!txSvc.beaconToAprsIs) return const SizedBox.shrink();
                    return _TxBadge();
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'rotate.aprs2.net:14580',
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
            Consumer<TxService>(
              builder: (_, txSvc, _) => SwitchListTile.adaptive(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Beacon'),
                value: txSvc.beaconToAprsIs,
                onChanged: (v) =>
                    context.read<TxService>().setBeaconToAprsIs(v),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: MeridianColors.danger,
                  side: const BorderSide(color: MeridianColors.danger),
                ),
                onPressed: onDisconnect,
                child: const Text('Disconnect'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatCount(int n) => '$n packet${n == 1 ? '' : 's'} received';
}

class _TncActiveCard extends StatelessWidget {
  const _TncActiveCard({
    required this.tncService,
    required this.packetCount,
    required this.onDisconnect,
  });

  final TncService tncService;
  final int packetCount;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = tncService.activeTransportType;
    final typeLabel = type == TransportType.ble ? 'BLE' : 'Serial';
    final deviceLabel = tncService.activeConfig?.port ?? typeLabel;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  type == TransportType.ble ? Symbols.bluetooth : Symbols.usb,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$typeLabel TNC',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                const MeridianStatusPill(
                  status: ConnectionStatus.connected,
                  label: 'Connected',
                ),
                const SizedBox(width: 8),
                Consumer<TxService>(
                  builder: (_, txSvc, _) {
                    if (!txSvc.beaconToTnc) return const SizedBox.shrink();
                    return _TxBadge();
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              deviceLabel,
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
            Consumer<TxService>(
              builder: (_, txSvc, _) => SwitchListTile.adaptive(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Beacon'),
                value: txSvc.beaconToTnc,
                onChanged: (v) => context.read<TxService>().setBeaconToTnc(v),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: MeridianColors.danger,
                  side: const BorderSide(color: MeridianColors.danger),
                ),
                onPressed: onDisconnect,
                child: const Text('Disconnect'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatCount(int n) => '$n packet${n == 1 ? '' : 's'} received';
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

class _TncUnavailableCard extends StatelessWidget {
  const _TncUnavailableCard({required this.message});

  final String message;

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
              const Icon(Symbols.info, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
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
