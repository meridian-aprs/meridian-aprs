import 'dart:async';

import 'package:meridian_aprs/core/connection/meridian_connection.dart';

/// Controllable [MeridianConnection] for use in registry and service tests.
class FakeMeridianConnection extends MeridianConnection {
  FakeMeridianConnection({
    required this.id,
    required this.displayName,
    required this.type,
    bool available = true,
  }) : _available = available;

  @override
  final String id;

  @override
  final String displayName;

  @override
  final ConnectionType type;

  final bool _available;

  @override
  bool get isAvailable => _available;

  // sync: true so status events fire synchronously in tests
  final _stateController = StreamController<ConnectionStatus>.broadcast(
    sync: true,
  );
  final _linesController = StreamController<String>.broadcast(sync: true);

  ConnectionStatus _status = ConnectionStatus.disconnected;
  bool _beaconingEnabled = true;
  bool settingsLoaded = false;

  @override
  ConnectionStatus get status => _status;

  @override
  Stream<ConnectionStatus> get connectionState => _stateController.stream;

  @override
  bool get isConnected => _status == ConnectionStatus.connected;

  @override
  bool get beaconingEnabled => _beaconingEnabled;

  @override
  Future<void> setBeaconingEnabled(bool enabled) async {
    _beaconingEnabled = enabled;
    notifyListeners();
  }

  @override
  Stream<String> get lines => _linesController.stream;

  @override
  Future<void> sendLine(String aprsLine) async {}

  @override
  Future<void> connect() async => setStatus(ConnectionStatus.connected);

  @override
  Future<void> disconnect() async => setStatus(ConnectionStatus.disconnected);

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _linesController.close();
    super.dispose();
  }

  @override
  Future<void> loadPersistedSettings() async {
    settingsLoaded = true;
  }

  // ---------------------------------------------------------------------------
  // Test helpers
  // ---------------------------------------------------------------------------

  void setStatus(ConnectionStatus s) {
    _status = s;
    if (!_stateController.isClosed) _stateController.add(s);
    notifyListeners();
  }

  void simulateLine(String line) {
    if (!_linesController.isClosed) _linesController.add(line);
  }
}
