import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/connection/ble_connection.dart';
import '../../core/transport/ble_constants.dart';
import 'ble_tnc_known_device.dart';

/// Bottom sheet for scanning and connecting to a BLE KISS TNC.
///
/// Default behaviour scans only for devices advertising one of the supported
/// BLE-KISS GATT services (the `aprs-specs` family — Mobilinkd, PicoAPRS,
/// B.B. Link, RPC, CA2RXU — and the Benshi/BTECH family — UV-Pro, Vero
/// VR-N76 / VR-N7500, Radioddity GA-5WB). The "Show all Bluetooth devices"
/// switch lifts the filter for DIY hardware (e.g. ESP32 builds advertising
/// Nordic UART) or troubleshooting.
///
/// Tapping "Connect" on a device calls [BleConnection.connectToDevice] (with
/// the resolved family hint when known) and closes the sheet (or calls
/// [onBack] when embedded inline).
///
/// Set [showDragHandle] to false and provide [onBack] when embedding this
/// widget inside another sheet instead of presenting it as a standalone modal.
/// Set [showBackButton] to false to suppress the back arrow even when [onBack]
/// is provided (useful when embedded in a screen that has its own nav).
class BleScannerSheet extends StatefulWidget {
  const BleScannerSheet({
    super.key,
    required this.bleConnection,
    this.showDragHandle = true,
    this.onBack,
    this.showBackButton = true,
  });

  final BleConnection bleConnection;

  /// Whether to render the drag handle at the top. Set to false when embedded
  /// inline inside another sheet that already has its own handle.
  final bool showDragHandle;

  /// Called after a successful connection (or when the user taps back) instead
  /// of [Navigator.pop]. Provide this when the widget is embedded inline.
  final VoidCallback? onBack;

  /// Whether to render the back arrow button in the title row.
  /// Defaults to true but can be suppressed when [onBack] is provided purely
  /// to override post-connect navigation (not to show a visible back control).
  final bool showBackButton;

  @override
  State<BleScannerSheet> createState() => _BleScannerSheetState();
}

class _BleScannerSheetState extends State<BleScannerSheet> {
  bool _scanning = false;
  bool _showAllDevices = false;
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

    // When the "show all" toggle is off, ask the OS to filter advertisements
    // at parse time using the supported family service UUIDs. This is
    // strictly equivalent to filtering in-app, but cheaper on the radio.
    final withServices = _showAllDevices
        ? const <Guid>[]
        : [Guid(kBleKissServiceUuid), Guid(kBenshiKissServiceUuid)];

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        withServices: withServices,
      );
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
      // Resolve the GATT family from advertisement data so the transport can
      // skip post-discovery autodetection. Falls back to null (autodetect)
      // when the device only advertised an unrelated service.
      final advertisedUuids = result.advertisementData.serviceUuids.map(
        (g) => g.str,
      );
      final family = bleKissFamilyForServiceUuids(advertisedUuids);
      await widget.bleConnection.connectToDevice(result.device, family: family);
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
              if (widget.onBack != null && widget.showBackButton)
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

          // Scan controls.
          if (_isBlePlatform && _bleError == null) ...[
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _scanning ? null : _startScan,
                  icon: Icon(_scanning ? Symbols.stop : Symbols.search),
                  label: Text(_scanning ? 'Scanning…' : 'Scan'),
                ),
                const SizedBox(width: 12),
                if (_scanning)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 4),

            // "Show all Bluetooth devices" advanced toggle.
            //
            // The default scan filters advertisements to known BLE-KISS family
            // service UUIDs. Lifting the filter is occasionally necessary for
            // DIY ESP32 builds that advertise Nordic UART (or no service UUID
            // at all) and for troubleshooting when a TNC isn't appearing.
            SwitchListTile.adaptive(
              title: Text(
                'Show all Bluetooth devices',
                style: theme.textTheme.bodyMedium,
              ),
              subtitle: Text(
                _showAllDevices
                    ? 'Showing every BLE device in range.'
                    : 'Filtering to known TNC families.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              value: _showAllDevices,
              onChanged: _scanning
                  ? null
                  : (value) {
                      setState(() {
                        _showAllDevices = value;
                        _deviceMap.clear();
                      });
                    },
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),

            // Scanning progress indicator.
            if (_scanning) const LinearProgressIndicator(),
            const SizedBox(height: 8),
          ],

          // Device list.
          if (devices.isNotEmpty)
            ...devices.map((result) {
              final advertisedName = result.device.platformName.isNotEmpty
                  ? result.device.platformName
                  : null;
              final known = BleTncKnownDevice.matchByName(advertisedName);
              final displayName =
                  known?.displayName ??
                  advertisedName ??
                  result.device.remoteId.str;
              final subtitle = known != null && advertisedName != null
                  ? '$advertisedName • RSSI ${result.rssi} dBm'
                  : 'RSSI: ${result.rssi} dBm';
              final leadingIcon = known?.icon ?? Symbols.bluetooth;
              final isConnecting =
                  _connectingDeviceId == result.device.remoteId.str;

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(leadingIcon),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Icon(
                          _rssiIcon(result.rssi),
                          size: 12,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                  title: Text(displayName),
                  subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
                  trailing: isConnecting
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator.adaptive(
                            strokeWidth: 2,
                          ),
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
                      _showAllDevices
                          ? 'Make sure your device is powered on and advertising.'
                          : 'Make sure your TNC is powered on and in range. '
                                'Toggle "Show all Bluetooth devices" if your TNC '
                                'is not in the supported list.',
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
