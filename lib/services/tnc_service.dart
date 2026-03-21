import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/transport/aprs_transport.dart' show ConnectionStatus;
import '../core/transport/serial_kiss_transport.dart';
import '../core/transport/tnc_config.dart';
import 'station_service.dart';

/// Manages the USB serial TNC connection lifecycle.
///
/// Wraps [SerialKissTransport], exposes connection state and decoded APRS
/// packets, and bridges received packets into [StationService] via
/// [StationService.ingestLine].
///
/// Register as a [ChangeNotifierProvider] in main.dart. Call
/// [loadPersistedConfig] once on startup.
class TncService extends ChangeNotifier {
  TncService(this._stationService);

  final StationService _stationService;

  SerialKissTransport? _transport;
  StreamSubscription<String>? _linesSub;
  StreamSubscription<ConnectionStatus>? _stateSub;

  ConnectionStatus _status = ConnectionStatus.disconnected;
  TncConfig? _activeConfig;

  /// Platform-guidance or error description. Set when status == error.
  String? _lastErrorMessage;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  ConnectionStatus get currentStatus => _status;
  TncConfig? get activeConfig => _activeConfig;
  String? get lastErrorMessage => _lastErrorMessage;

  /// Stream of [ConnectionStatus] changes.
  Stream<ConnectionStatus> get connectionState => _stateController.stream;
  final _stateController = StreamController<ConnectionStatus>.broadcast();

  /// Connect to the TNC described by [config].
  ///
  /// Saves the config to SharedPreferences so it can be restored on the next
  /// launch. On failure, transitions to [ConnectionStatus.error] and sets
  /// [lastErrorMessage].
  Future<void> connect(TncConfig config) async {
    await disconnect();
    _activeConfig = config;
    await _saveConfig(config);

    final transport = SerialKissTransport(config);
    _transport = transport;

    // Mirror transport state into our own stream.
    _stateSub = transport.connectionState.listen((s) {
      _status = s;
      _stateController.add(s);
      notifyListeners();
    });

    // Pipe decoded APRS lines into StationService.
    _linesSub = transport.lines.listen(_stationService.ingestLine);

    try {
      await transport.connect();
    } catch (e) {
      _lastErrorMessage = _errorMessage(e.toString(), config.port);
      _status = ConnectionStatus.error;
      _stateController.add(ConnectionStatus.error);
      notifyListeners();
    }
  }

  /// Disconnect and release resources.
  Future<void> disconnect() async {
    await _linesSub?.cancel();
    _linesSub = null;
    await _stateSub?.cancel();
    _stateSub = null;
    await _transport?.disconnect();
    _transport = null;
    if (_status != ConnectionStatus.disconnected) {
      _status = ConnectionStatus.disconnected;
      _stateController.add(ConnectionStatus.disconnected);
      notifyListeners();
    }
  }

  /// Returns available serial port names. Empty on non-desktop platforms.
  List<String> availablePorts() => SerialKissTransport.availablePorts();

  /// Load the previously-persisted [TncConfig] from SharedPreferences.
  ///
  /// Call once on app startup. Does not automatically connect — the user
  /// must tap Connect in the UI.
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
    disconnect();
    _stateController.close();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Internal
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

  String _errorMessage(String error, String port) {
    // Provide platform-specific guidance for permission errors.
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
}
