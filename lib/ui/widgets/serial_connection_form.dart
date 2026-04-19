import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/connection/meridian_connection.dart';
import '../../core/connection/serial_connection.dart';
import '../../core/transport/tnc_config.dart';
import '../../core/transport/tnc_preset.dart';

/// Reusable form for selecting a TNC preset + serial port and initiating a
/// serial connection.
///
/// Used by:
///   - [ConnectionScreen] (settings tab) — no callback, form stays alive and
///     lets the user disconnect/reconnect.
///   - Onboarding `ConnectionPage` — passes [onConnected] to advance the flow
///     once the connection is live.
class SerialConnectionForm extends StatefulWidget {
  const SerialConnectionForm({
    super.key,
    required this.connection,
    this.onConnected,
    this.showConnectedHint = true,
  });

  /// The serial connection instance to drive.
  final SerialConnection connection;

  /// Optional callback fired once when the connection transitions into
  /// [ConnectionStatus.connected]. Useful for navigational contexts.
  final VoidCallback? onConnected;

  /// Whether to show the "Connected — disconnect from the card above" hint
  /// when the connection is live. Onboarding can set this false to avoid
  /// confusing copy that references a card that isn't there.
  final bool showConnectedHint;

  @override
  State<SerialConnectionForm> createState() => _SerialConnectionFormState();
}

class _SerialConnectionFormState extends State<SerialConnectionForm> {
  late TncPreset _selectedPreset;
  List<String> _availablePorts = [];
  String? _selectedPort;
  bool _firedOnConnected = false;

  @override
  void initState() {
    super.initState();

    // Restore preset/port from the connection if it already has a config.
    final activeConfig = widget.connection.activeConfig;
    _selectedPreset = TncPreset.all.firstWhere(
      (p) => p.id == activeConfig?.presetId,
      orElse: () => TncPreset.mobilinkdTnc4,
    );
    _refreshSerialPorts(initial: activeConfig?.port);

    widget.connection.addListener(_onConnectionChanged);
  }

  @override
  void dispose() {
    widget.connection.removeListener(_onConnectionChanged);
    super.dispose();
  }

  void _onConnectionChanged() {
    if (!mounted) return;
    if (widget.onConnected != null &&
        !_firedOnConnected &&
        widget.connection.status == ConnectionStatus.connected) {
      _firedOnConnected = true;
      widget.onConnected!();
    }
    setState(() {});
  }

  void _refreshSerialPorts({String? initial}) {
    final ports = widget.connection.availablePorts();
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

  Future<void> _connect() async {
    if (_selectedPort == null) return;
    final config = TncConfig.fromPreset(_selectedPreset, port: _selectedPort!);
    await widget.connection.connectWithConfig(config);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conn = widget.connection;
    final isConnected = conn.status == ConnectionStatus.connected;
    final isConnecting = conn.status == ConnectionStatus.connecting;
    final errorMessage = conn.lastErrorMessage;

    return Column(
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
                              () => _refreshSerialPorts(initial: _selectedPort),
                            ),
                    ),
                  ],
                ),

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

        if (isConnected && widget.showConnectedHint)
          Text(
            'Connected — disconnect from the card above.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else if (!isConnected) ...[
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
                  : _connect,
              child: Text(isConnecting ? 'Connecting\u2026' : 'Connect'),
            ),
          ),
        ],
      ],
    );
  }
}
