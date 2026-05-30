import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/connection/classic_bt_connection.dart';
import '../../core/transport/classic_bt_spp_channel.dart';

/// Paired-device picker for the Classic Bluetooth SPP transport (ADR-069).
///
/// Pairing is owned by the OS — this lists only already-bonded devices
/// (`BluetoothAdapter.bondedDevices`) and connects to the chosen one. There is
/// deliberately **no scan**: the user pairs the TNC in Android Bluetooth
/// settings first, then picks it here.
///
/// Requests the `BLUETOOTH_CONNECT` runtime permission (Android 12+/API 31+)
/// before listing; the native bridge also degrades gracefully if it is denied.
class ClassicBtDeviceList extends StatefulWidget {
  const ClassicBtDeviceList({super.key, required this.connection});

  final ClassicBtConnection connection;

  @override
  State<ClassicBtDeviceList> createState() => _ClassicBtDeviceListState();
}

enum _LoadState { loading, denied, error, ready }

class _ClassicBtDeviceListState extends State<ClassicBtDeviceList> {
  _LoadState _state = _LoadState.loading;
  List<ClassicBtPairedDevice> _devices = const [];
  String? _connectingAddress;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _state = _LoadState.loading);

    // BLUETOOTH_CONNECT is required to read bonded devices and open RFCOMM on
    // API 31+. On older Android the request resolves granted immediately.
    final status = await Permission.bluetoothConnect.request();
    if (!status.isGranted) {
      if (mounted) setState(() => _state = _LoadState.denied);
      return;
    }

    try {
      final devices = await widget.connection.pairedDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _state = _LoadState.ready;
      });
    } catch (_) {
      if (mounted) setState(() => _state = _LoadState.error);
    }
  }

  Future<void> _connect(ClassicBtPairedDevice device) async {
    setState(() => _connectingAddress = device.address);
    try {
      await widget.connection.connectToDevice(
        device.address,
        name: device.name,
      );
    } finally {
      if (mounted) setState(() => _connectingAddress = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Pair your TNC in Android Bluetooth settings before connecting here.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        switch (_state) {
          _LoadState.loading => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator.adaptive()),
          ),
          _LoadState.denied => _MessageCard(
            icon: Symbols.bluetooth_disabled,
            title: 'Bluetooth permission needed',
            body:
                'Grant the Nearby devices / Bluetooth permission to list your '
                'paired TNCs.',
            actionLabel: 'Open settings',
            onAction: openAppSettings,
          ),
          _LoadState.error => _MessageCard(
            icon: Symbols.error,
            title: 'Could not list devices',
            body: 'Make sure Bluetooth is turned on, then try again.',
            actionLabel: 'Retry',
            onAction: _load,
          ),
          _LoadState.ready when _devices.isEmpty => _MessageCard(
            icon: Symbols.bluetooth_searching,
            title: 'No paired devices',
            body: 'Pair your TNC in Android Bluetooth settings, then refresh.',
            actionLabel: 'Refresh',
            onAction: _load,
          ),
          _LoadState.ready => Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (final device in _devices)
                  ListTile(
                    leading: const Icon(Symbols.bluetooth),
                    title: Text(device.name),
                    subtitle: Text(device.address),
                    trailing: _connectingAddress == device.address
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator.adaptive(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Symbols.chevron_right),
                    enabled: _connectingAddress == null,
                    onTap: () => _connect(device),
                  ),
              ],
            ),
          ),
        },
        if (_state == _LoadState.ready && _devices.isNotEmpty) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _connectingAddress == null ? _load : null,
              icon: const Icon(Symbols.refresh),
              label: const Text('Refresh'),
            ),
          ),
        ],
      ],
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

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
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(body, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
