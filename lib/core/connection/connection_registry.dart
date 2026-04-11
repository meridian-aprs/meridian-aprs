import 'dart:async';

import 'package:flutter/foundation.dart';

import 'meridian_connection.dart';

export 'meridian_connection.dart';

/// Holds all registered [MeridianConnection] instances and provides a unified
/// view of connection state across all transports.
///
/// Connections are registered at app startup via [register]. The registry
/// listens to each connection and re-notifies its own listeners whenever any
/// connection changes state, so UI widgets only need to watch one provider.
///
/// The [lines] stream multiplexes incoming APRS text from every connection,
/// tagging each line with its source [ConnectionType].
class ConnectionRegistry extends ChangeNotifier {
  final List<MeridianConnection> _connections = [];
  final List<StreamSubscription<String>> _lineSubs = [];

  final _linesController =
      StreamController<({String line, ConnectionType source})>.broadcast();

  // ---------------------------------------------------------------------------
  // Registration
  // ---------------------------------------------------------------------------

  /// Register a connection and begin listening to its state changes.
  ///
  /// Must be called before [loadAllSettings] and before any connections are
  /// opened. Forwarding from [conn.lines] starts immediately.
  void register(MeridianConnection conn) {
    _connections.add(conn);
    conn.addListener(notifyListeners);
    _lineSubs.add(
      conn.lines.listen((line) {
        if (!_linesController.isClosed) {
          _linesController.add((line: line, source: conn.type));
        }
      }),
    );
  }

  // ---------------------------------------------------------------------------
  // Accessors
  // ---------------------------------------------------------------------------

  /// All registered connections regardless of availability or state.
  List<MeridianConnection> get all => List.unmodifiable(_connections);

  /// Connections that are supported on the current platform.
  List<MeridianConnection> get available =>
      _connections.where((c) => c.isAvailable).toList();

  /// Connections currently in the [ConnectionStatus.connected] state.
  List<MeridianConnection> get connected =>
      _connections.where((c) => c.isConnected).toList();

  /// True if at least one connection is [ConnectionStatus.connected].
  bool get isAnyConnected => _connections.any((c) => c.isConnected);

  /// Aggregated status across all connections, following the priority order:
  ///   connected > reconnecting > connecting > waitingForDevice > error > disconnected
  ConnectionStatus get aggregateStatus {
    if (_connections.isEmpty) return ConnectionStatus.disconnected;
    const priority = [
      ConnectionStatus.connected,
      ConnectionStatus.reconnecting,
      ConnectionStatus.connecting,
      ConnectionStatus.waitingForDevice,
      ConnectionStatus.error,
      ConnectionStatus.disconnected,
    ];
    for (final s in priority) {
      if (_connections.any((c) => c.status == s)) return s;
    }
    return ConnectionStatus.disconnected;
  }

  /// Multiplexed APRS text lines from all connections, tagged with their
  /// source [ConnectionType].
  Stream<({String line, ConnectionType source})> get lines =>
      _linesController.stream;

  /// Look up a connection by its [MeridianConnection.id].
  MeridianConnection? byId(String id) {
    for (final c in _connections) {
      if (c.id == id) return c;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Call [MeridianConnection.loadPersistedSettings] on every registered
  /// connection. Awaits all in parallel.
  Future<void> loadAllSettings() =>
      Future.wait(_connections.map((c) => c.loadPersistedSettings()));

  @override
  void dispose() {
    for (final sub in _lineSubs) {
      sub.cancel();
    }
    _lineSubs.clear();
    for (final c in _connections) {
      c.removeListener(notifyListeners);
    }
    _linesController.close();
    super.dispose();
  }
}
