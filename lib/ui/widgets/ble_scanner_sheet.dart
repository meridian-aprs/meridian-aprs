import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/transport/ble_constants.dart';
import '../../core/transport/tnc_preset.dart';
import '../../services/tnc_service.dart';

/// Filter option for the BLE device scanner.
///
/// [_BleFilterOption.all] shows every discovered device. A preset-based
/// option limits results to devices whose advertised GATT service UUIDs
/// match the known UUID for that TNC model.
class _BleFilterOption {
  const _BleFilterOption({required this.label, this.serviceUuid});

  /// Display name shown in the dropdown.
  final String label;

  /// If non-null, only devices advertising this service UUID are shown.
  final String? serviceUuid;

  static const _BleFilterOption all = _BleFilterOption(label: 'All Devices');

  /// One entry per TNC preset with a known BLE service UUID.
  static final List<_BleFilterOption> presetOptions = [
    _BleFilterOption(
      label: TncPreset.mobilinkdTnc4.displayName,
      serviceUuid: kMobilinkdServiceUuid,
    ),
  ];

  static List<_BleFilterOption> get values => [all, ...presetOptions];
}

/// Bottom sheet for scanning and connecting to a BLE KISS TNC.
///
/// Scans for nearby BLE devices and optionally filters results by TNC type
/// selected in the dropdown. "All Devices" shows everything; selecting a
/// specific TNC model limits results to devices advertising that TNC's GATT
/// service UUID.
///
/// Tapping "Connect" on a device calls [TncService.connectBle] and closes
/// the sheet (or calls [onBack] when embedded inline).
///
/// Set [showDragHandle] to false and provide [onBack] when embedding this
/// widget inside another sheet instead of presenting it as a standalone modal.
class BleScannerSheet extends StatefulWidget {
  const BleScannerSheet({
    super.key,
    required this.tncService,
    this.showDragHandle = true,
    this.onBack,
  });

  final TncService tncService;

  /// Whether to render the drag handle at the top. Set to false when embedded
  /// inline inside another sheet that already has its own handle.
  final bool showDragHandle;

  /// Called after a successful connection (or when the user taps back) instead
  /// of [Navigator.pop]. Provide this when the widget is embedded inline.
  final VoidCallback? onBack;

  @override
  State<BleScannerSheet> createState() => _BleScannerSheetState();
}

class _BleScannerSheetState extends State<BleScannerSheet> {
  bool _scanning = false;
  _BleFilterOption _filter = _BleFilterOption.presetOptions.first;
  String? _bleError;
  String? _connectingDeviceId;

  // Track unique devices by remoteId (deduplicates scan updates).
  final _deviceMap = <DeviceIdentifier, ScanResult>{};

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;

  @override
  void initState() {
    super.initState();
    _checkAdapter();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _adapterSub?.cancel();
    if (_scanning) FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _checkAdapter() async {
    if (kIsWeb) {
      setState(() => _bleError = 'BLE TNC is not available on web.');
      return;
    }
    // On desktop Linux/macOS/Windows BLE may be unavailable.
    final state = await FlutterBluePlus.adapterState.first;
    if (state == BluetoothAdapterState.off) {
      setState(
        () => _bleError =
            'Bluetooth is off. Enable it in Settings to connect a BLE TNC.',
      );
    } else if (state == BluetoothAdapterState.unavailable) {
      setState(() => _bleError = 'Bluetooth is not available on this device.');
    } else if (state == BluetoothAdapterState.unauthorized) {
      setState(
        () => _bleError = 'Bluetooth permission is required to connect a TNC.',
      );
    }
  }

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _deviceMap.clear();
      _bleError = null;
    });

    _scanSub?.cancel();

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    } on FlutterBluePlusException catch (e) {
      setState(() {
        _bleError = _friendlyBleError(e.description ?? e.toString());
        _scanning = false;
      });
      return;
    }

    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      if (!mounted) return;
      setState(() {
        for (final r in results) {
          if (_filter.serviceUuid != null) {
            final advertisedUuids = r.advertisementData.serviceUuids
                .map((g) => g.str.toLowerCase())
                .toList();
            if (!advertisedUuids.contains(_filter.serviceUuid!.toLowerCase())) {
              continue;
            }
          }
          _deviceMap[r.device.remoteId] = r;
        }
      });
    });

    // FlutterBluePlus stops on timeout; listen for adapter state to detect
    // early stop.
    FlutterBluePlus.isScanning.listen((isScanning) {
      if (!isScanning && mounted) {
        setState(() => _scanning = false);
      }
    });
  }

  Future<void> _connect(ScanResult result) async {
    await FlutterBluePlus.stopScan();
    setState(() {
      _connectingDeviceId = result.device.remoteId.str;
      _bleError = null;
    });

    try {
      await widget.tncService.connectBle(result.device);
      if (mounted) {
        if (widget.onBack != null) {
          widget.onBack!();
        } else {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _connectingDeviceId = null;
          _bleError =
              'Could not connect to ${result.device.platformName.isNotEmpty ? result.device.platformName : "device"}. Try again.';
        });
      }
    }
  }

  String _friendlyBleError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('permission') || lower.contains('unauthorized')) {
      return 'Bluetooth permission is required to connect a TNC.';
    }
    if (lower.contains('off') || lower.contains('adapter')) {
      return 'Bluetooth is off. Enable it in Settings to connect a BLE TNC.';
    }
    return raw;
  }

  IconData _rssiIcon(int rssi) {
    if (rssi >= -60) return Symbols.signal_cellular_4_bar;
    if (rssi >= -70) return Symbols.network_wifi_3_bar;
    if (rssi >= -80) return Symbols.network_wifi_2_bar;
    return Symbols.network_wifi_1_bar;
  }

  bool get _isBlePlatform =>
      !kIsWeb &&
      (Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isLinux ||
          Platform.isWindows);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final devices = _deviceMap.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle — omitted when embedded inside another sheet.
          if (widget.showDragHandle)
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

          // Title row.
          Row(
            children: [
              if (widget.onBack != null)
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: widget.onBack,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                )
              else
                Icon(
                  Symbols.bluetooth_searching,
                  color: theme.colorScheme.primary,
                ),
              const SizedBox(width: 10),
              Text('BLE TNC', style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 16),

          // Error banner.
          if (_bleError != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Symbols.error_outline,
                    color: theme.colorScheme.onErrorContainer,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _bleError!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Controls row: scan button + TNC filter dropdown.
          if (_isBlePlatform && _bleError == null) ...[
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _scanning ? null : _startScan,
                  icon: Icon(_scanning ? Symbols.stop : Symbols.search),
                  label: Text(_scanning ? 'Scanning\u2026' : 'Scan'),
                ),
                const SizedBox(width: 12),
                if (_scanning) ...[
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                ],
                const Spacer(),
                // TNC type filter dropdown.
                DropdownButton<_BleFilterOption>(
                  value: _filter,
                  isDense: true,
                  items: _BleFilterOption.values.map((option) {
                    return DropdownMenuItem<_BleFilterOption>(
                      value: option,
                      child: Text(
                        option.label,
                        style: theme.textTheme.bodySmall,
                      ),
                    );
                  }).toList(),
                  onChanged: (option) {
                    if (option != null) {
                      setState(() {
                        _filter = option;
                        _deviceMap.clear();
                      });
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Scanning progress indicator.
            if (_scanning) const LinearProgressIndicator(),
            const SizedBox(height: 8),
          ],

          // Device list.
          if (devices.isNotEmpty)
            ...devices.map((result) {
              final name = result.device.platformName.isNotEmpty
                  ? result.device.platformName
                  : result.device.remoteId.str;
              final isConnecting =
                  _connectingDeviceId == result.device.remoteId.str;

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(_rssiIcon(result.rssi)),
                  title: Text(name),
                  subtitle: Text(
                    'RSSI: ${result.rssi} dBm',
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: isConnecting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : FilledButton.tonal(
                          onPressed: _connectingDeviceId != null
                              ? null
                              : () => _connect(result),
                          child: const Text('Connect'),
                        ),
                ),
              );
            })
          else if (!_scanning && _bleError == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Symbols.bluetooth_disabled,
                      size: 48,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No TNC devices found.',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Make sure your TNC is powered on and in range.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
