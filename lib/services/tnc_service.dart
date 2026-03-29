import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/packet/aprs_packet.dart' show PacketSource;
import '../core/packet/aprs_parser.dart';
import '../core/transport/serial_kiss_transport.dart';
import '../core/transport/tnc_config.dart';
import '../core/transport/transport_manager.dart';
import 'station_service.dart';

export '../core/transport/transport_manager.dart'
    show TransportType, ConnectionStatus;

/// Manages the TNC connection lifecycle and bridges decoded packets to
/// [StationService].
///
/// Owns a [TransportManager] that holds the currently active [KissTncTransport]
/// (serial or BLE). Raw AX.25 frames from the transport are parsed here via
/// [AprsParser.parseFrame] and forwarded to [StationService.ingestLine].
///
/// Register as a [ChangeNotifierProvider] in main.dart. Call
/// [loadPersistedConfig] once on startup.
class TncService extends ChangeNotifier {
  TncService(this._stationService);

  final StationService _stationService;
  final _transportManager = TransportManager();
  final _aprsParser = AprsParser();

  StreamSubscription<Uint8List>? _frameSub;
  StreamSubscription<ConnectionStatus>? _stateSub;

  TncConfig? _activeConfig;

  /// Platform-guidance or error description. Set when status == error.
  String? _lastErrorMessage;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  ConnectionStatus get currentStatus => _transportManager.currentStatus;
  TncConfig? get activeConfig => _activeConfig;
  String? get lastErrorMessage => _lastErrorMessage;
  TransportType get activeTransportType => _transportManager.activeType;

  /// Expose the transport manager for widgets that need direct access
  /// (e.g. BLE scanner passing a device to connect).
  TransportManager get transportManager => _transportManager;

  /// Stream of [ConnectionStatus] changes (serial or BLE).
  Stream<ConnectionStatus> get connectionState => _stateController.stream;
  final _stateController = StreamController<ConnectionStatus>.broadcast();

  /// Connect to the serial TNC described by [config].
  ///
  /// Saves the config to SharedPreferences. On failure, transitions to
  /// [ConnectionStatus.error] and sets [lastErrorMessage].
  Future<void> connect(TncConfig config) async {
    await _cancelBridge();
    _activeConfig = config;
    await _saveConfig(config);

    _attachBridge();

    try {
      await _transportManager.connectSerial(config);
    } catch (e) {
      _lastErrorMessage = _serialErrorMessage(e.toString(), config.port);
      _stateController.add(ConnectionStatus.error);
      notifyListeners();
    }
  }

  /// Connect to a BLE TNC device.
  ///
  /// On failure, transitions to [ConnectionStatus.error] and sets
  /// [lastErrorMessage].
  Future<void> connectBle(BluetoothDevice device) async {
    await _cancelBridge();
    _attachBridge();

    try {
      await _transportManager.connectBle(device);
    } catch (e) {
      _lastErrorMessage = _bleErrorMessage(e.toString(), device.platformName);
      _stateController.add(ConnectionStatus.error);
      notifyListeners();
    }
  }

  /// Disconnect and release resources.
  Future<void> disconnect() async {
    // Disconnect first so the final ConnectionStatus.disconnected event flows
    // through _stateSub → _stateController before the bridge is torn down.
    await _transportManager.disconnect();
    await _cancelBridge();
  }

  /// Returns available serial port names. Empty on non-desktop platforms or
  /// when the native serial library cannot be loaded (e.g. in test environments
  /// without a real serial driver installed).
  List<String> availablePorts() {
    try {
      return SerialKissTransport.availablePorts();
    } catch (_) {
      return const [];
    }
  }

  /// Persist [config] as the active TNC configuration without connecting.
  ///
  /// Use this to save settings changes from the Settings screen.
  Future<void> updateConfig(TncConfig config) async {
    _activeConfig = config;
    await _saveConfig(config);
    notifyListeners();
  }

  /// Load the previously-persisted [TncConfig] from SharedPreferences.
  ///
  /// Call once on app startup. Does not automatically connect.
  Future<void> loadPersistedConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final map = {
      for (final key in prefs.getKeys())
        if (key.startsWith('tnc_')) key: prefs.get(key),
    };
    _activeConfig = TncConfig.fromPrefsMap(map);
    notifyListeners();
  }

  @override
  void dispose() {
    _cancelBridge();
    _transportManager.dispose();
    _stateController.close();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Internal — frame bridge
  // ---------------------------------------------------------------------------

  /// Subscribe to the transport manager's streams.
  ///
  /// Must be called before connecting (to capture state transitions from
  /// `connecting` onward).
  void _attachBridge() {
    _stateSub = _transportManager.connectionState.listen((s) {
      _stateController.add(s);
      notifyListeners();
    });
    _frameSub = _transportManager.frameStream.listen(_onFrame);
  }

  Future<void> _cancelBridge() async {
    await _frameSub?.cancel();
    _frameSub = null;
    await _stateSub?.cancel();
    _stateSub = null;
  }

  void _onFrame(Uint8List frameBytes) {
    final packet = _aprsParser.parseFrame(frameBytes);
    // An empty rawLine means AX.25 decode failed; skip silently.
    if (packet.rawLine.isNotEmpty) {
      _stationService.ingestLine(packet.rawLine, source: PacketSource.tnc);
    }
  }

  // ---------------------------------------------------------------------------
  // Internal — persistence
  // ---------------------------------------------------------------------------

  Future<void> _saveConfig(TncConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in config.toPrefsMap().entries) {
      final value = entry.value;
      if (value is String) await prefs.setString(entry.key, value);
      if (value is int) await prefs.setInt(entry.key, value);
      if (value is bool) await prefs.setBool(entry.key, value);
    }
  }

  String _serialErrorMessage(String error, String port) {
    final lower = error.toLowerCase();
    if (lower.contains('permission') ||
        lower.contains('access denied') ||
        lower.contains('eacces')) {
      if (defaultTargetPlatform == TargetPlatform.linux) {
        return 'Permission denied on $port.\n'
            'Add your user to the dialout group:\n'
            '  sudo usermod -aG dialout \$USER\n'
            'Then log out and back in.';
      } else if (defaultTargetPlatform == TargetPlatform.macOS) {
        return 'Permission denied on $port.\n'
            'Grant serial port access in:\n'
            '  System Settings › Privacy & Security';
      }
      return 'Permission denied on $port. Check your serial port permissions.';
    }
    if (lower.contains('no such file') ||
        lower.contains('not found') ||
        lower.contains('enoent')) {
      return 'Port $port not found. Is the TNC plugged in?';
    }
    return 'Could not connect to $port: $error';
  }

  String _bleErrorMessage(String error, String deviceName) {
    final lower = error.toLowerCase();
    if (lower.contains('permission') || lower.contains('unauthorized')) {
      return 'Bluetooth permission is required to connect a TNC.';
    }
    if (lower.contains('timeout') || lower.contains('canceled')) {
      return 'Could not connect to $deviceName. Try again.';
    }
    if (lower.contains('service') && lower.contains('not found')) {
      return '$deviceName does not appear to be a compatible KISS TNC.';
    }
    return 'Could not connect to $deviceName: $error';
  }
}
