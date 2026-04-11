/// TX router that fans out outgoing APRS packets across all connected and
/// beaconing-enabled [MeridianConnection]s.
///
/// The hierarchy for per-message routing is Serial > BLE > APRS-IS unless
/// overridden by the [forceVia] parameter on [sendLine].
///
/// Backward-compat note: [TxTransportPref], [preference], [effective],
/// [aprsIsAvailable], [tncAvailable], [beaconToAprsIs], [beaconToTnc],
/// [setBeaconToAprsIs], [setBeaconToTnc], [setPreference], and
/// [loadPersistedPreference] are retained for UI compatibility until Phase 6.
/// At that point they will be removed in favour of per-connection
/// [MeridianConnection.beaconingEnabled] and [ConnectionRegistry].
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/connection/connection_registry.dart';

// ---------------------------------------------------------------------------
// Backward-compat: per-message transport override enum
// ---------------------------------------------------------------------------

/// Whether to send via APRS-IS, TNC, or let the hierarchy decide.
///
/// Retained for Phase 6 UI compatibility. Will be replaced by
/// [ConnectionType]-based forceVia parameter.
enum TxTransportPref { auto, aprsIs, tnc }

// ---------------------------------------------------------------------------
// Banner events
// ---------------------------------------------------------------------------

/// Events emitted by [TxService] to drive banner UI.
sealed class TxEvent {}

/// A TNC (BLE or Serial) disconnected while RF was the active TX path.
class TxEventTncDisconnected extends TxEvent {}

/// A TNC (BLE or Serial) reconnected — offer to switch back to RF.
class TxEventTncReconnected extends TxEvent {}

// ---------------------------------------------------------------------------
// TxService
// ---------------------------------------------------------------------------

class TxService extends ChangeNotifier {
  TxService(this._registry) {
    _registry.addListener(_onRegistryChanged);
  }

  final ConnectionRegistry _registry;
  final _eventController = StreamController<TxEvent>.broadcast();

  // Compat: stored preference for Phase 6 UI to read (no longer drives routing)
  TxTransportPref _preference = TxTransportPref.auto;
  bool _userHasExplicitlySet = false;
  bool _tncWasConnected = false;

  // ---------------------------------------------------------------------------
  // Public API — routing
  // ---------------------------------------------------------------------------

  /// Stream of [TxEvent]s for UI banner display (TNC connect/disconnect).
  Stream<TxEvent> get events => _eventController.stream;

  /// Human-readable label for the effective TX path.
  ///
  /// e.g. `"Auto [Serial]"`, `"Auto [BLE]"`, `"Auto [APRS-IS]"`.
  String get resolvedTxLabel {
    final conn = _effectiveConnection();
    if (conn == null) return 'Auto';
    return switch (conn.type) {
      ConnectionType.serialTnc => 'Auto [Serial]',
      ConnectionType.bleTnc => 'Auto [BLE]',
      ConnectionType.aprsIs => 'Auto [APRS-IS]',
    };
  }

  /// Send [aprsLine] via the resolved effective connection.
  ///
  /// When [forceVia] is provided, the first connected connection of that type
  /// is used; otherwise the hierarchy (Serial > BLE > APRS-IS) is applied.
  Future<void> sendLine(String aprsLine, {ConnectionType? forceVia}) async {
    final conn = _effectiveConnection(forceVia: forceVia);
    if (conn == null) return;
    await conn.sendLine(aprsLine);
  }

  /// Fan out [aprsLine] to every connection where
  /// [MeridianConnection.beaconingEnabled] is true and the connection is live.
  ///
  /// Each connection is attempted independently — a failure on one does not
  /// block the others.
  Future<void> sendBeacon(String aprsLine) async {
    for (final conn in _registry.all) {
      if (conn.beaconingEnabled && conn.isConnected) {
        try {
          await conn.sendLine(aprsLine);
        } catch (e) {
          debugPrint('TxService: sendBeacon via ${conn.id} failed: $e');
        }
      }
    }
  }

  /// Send [aprsLine] to the first connected TNC (Serial takes priority over BLE).
  ///
  /// Used by [BackgroundServiceManager] to forward background-isolate IPC
  /// beacon requests to the live TNC connection.
  Future<void> sendViaTncOnly(String aprsLine) async {
    final conn = _registry.all
        .where(
          (c) =>
              (c.type == ConnectionType.serialTnc ||
                  c.type == ConnectionType.bleTnc) &&
              c.isConnected,
        )
        .firstOrNull;
    if (conn != null) {
      await conn.sendLine(aprsLine);
    }
  }

  // ---------------------------------------------------------------------------
  // Backward-compat getters (Phase 6 will remove these)
  // ---------------------------------------------------------------------------

  /// True when an APRS-IS connection is currently live.
  bool get aprsIsAvailable => _registry.all.any(
    (c) => c.type == ConnectionType.aprsIs && c.isConnected,
  );

  /// True when any TNC (BLE or Serial) is currently live.
  bool get tncAvailable => _registry.all.any(
    (c) =>
        (c.type == ConnectionType.bleTnc ||
            c.type == ConnectionType.serialTnc) &&
        c.isConnected,
  );

  /// Effective APRS-IS beaconing flag, derived from the registered
  /// [AprsIsConnection]'s [MeridianConnection.beaconingEnabled].
  bool get beaconToAprsIs =>
      _registry.byId('aprs_is')?.beaconingEnabled ?? true;

  /// Effective TNC beaconing flag, derived from any registered TNC
  /// connection's [MeridianConnection.beaconingEnabled].
  bool get beaconToTnc => _registry.all.any(
    (c) =>
        (c.type == ConnectionType.bleTnc ||
            c.type == ConnectionType.serialTnc) &&
        c.beaconingEnabled,
  );

  /// Update APRS-IS beaconing on the registered [AprsIsConnection].
  Future<void> setBeaconToAprsIs(bool v) async {
    final conn = _registry.byId('aprs_is');
    if (conn != null) await conn.setBeaconingEnabled(v);
  }

  /// Update beaconing on every registered TNC connection.
  Future<void> setBeaconToTnc(bool v) async {
    for (final conn in _registry.all) {
      if (conn.type == ConnectionType.bleTnc ||
          conn.type == ConnectionType.serialTnc) {
        await conn.setBeaconingEnabled(v);
      }
    }
  }

  /// The stored per-message transport preference (compat; no longer drives routing).
  TxTransportPref get preference => _preference;

  /// Whether the user has explicitly set a preference (compat).
  bool get userHasExplicitlySet => _userHasExplicitlySet;

  /// Resolved effective preference (compat; computed from registry availability).
  TxTransportPref get effective {
    if (_preference == TxTransportPref.auto) {
      return tncAvailable ? TxTransportPref.tnc : TxTransportPref.aprsIs;
    }
    if (_preference == TxTransportPref.tnc && !tncAvailable) {
      return TxTransportPref.aprsIs;
    }
    return _preference;
  }

  /// Persist a per-message transport preference (compat).
  Future<void> setPreference(
    TxTransportPref pref, {
    bool explicit = true,
  }) async {
    _preference = pref;
    if (explicit) _userHasExplicitlySet = true;
    notifyListeners();
  }

  /// No-op. TX settings are now per-connection and loaded via
  /// [ConnectionRegistry.loadAllSettings].
  Future<void> loadPersistedPreference() async {
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _registry.removeListener(_onRegistryChanged);
    _eventController.close();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  MeridianConnection? _effectiveConnection({ConnectionType? forceVia}) {
    if (forceVia != null) {
      return _registry.all
          .where((c) => c.type == forceVia && c.isConnected)
          .firstOrNull;
    }
    const order = [
      ConnectionType.serialTnc,
      ConnectionType.bleTnc,
      ConnectionType.aprsIs,
    ];
    for (final type in order) {
      final conn = _registry.all
          .where((c) => c.type == type && c.isConnected)
          .firstOrNull;
      if (conn != null) return conn;
    }
    return null;
  }

  void _onRegistryChanged() {
    final tncNowConnected = tncAvailable;
    if (_tncWasConnected && !tncNowConnected) {
      _eventController.add(TxEventTncDisconnected());
    } else if (!_tncWasConnected && tncNowConnected) {
      _eventController.add(TxEventTncReconnected());
    }
    _tncWasConnected = tncNowConnected;
    notifyListeners();
  }
}
