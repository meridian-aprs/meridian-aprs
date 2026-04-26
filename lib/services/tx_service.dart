/// TX router that fans out outgoing APRS packets across all connected and
/// beaconing-enabled [MeridianConnection]s.
///
/// Per-message routing follows the unconditional Serial > BLE > APRS-IS
/// hierarchy (ADR-029). Per-beacon routing honours
/// [MeridianConnection.beaconingEnabled] on each connection. There is no
/// per-message transport override.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/connection/connection_registry.dart';
import '../core/packet/aprs_packet.dart';
import 'station_settings_service.dart';

// ---------------------------------------------------------------------------
// Banner events
// ---------------------------------------------------------------------------

/// Events emitted by [TxService] to drive banner UI.
sealed class TxEvent {}

/// A TNC (BLE or Serial) disconnected while RF was the active TX path.
class TxEventTncDisconnected extends TxEvent {}

/// A TNC (BLE or Serial) reconnected — notify the user that RF is live again.
class TxEventTncReconnected extends TxEvent {}

// ---------------------------------------------------------------------------
// TxService
// ---------------------------------------------------------------------------

class TxService extends ChangeNotifier {
  TxService(this._registry, this._settings, {this.onSent}) {
    _registry.addListener(_onRegistryChanged);
  }

  final ConnectionRegistry _registry;
  final StationSettingsService _settings;
  final _eventController = StreamController<TxEvent>.broadcast();

  /// Invoked once per successful per-connection transmit so outgoing packets
  /// can be recorded in the packet log tagged with their actual transport.
  final void Function(String aprsLine, PacketSource source)? onSent;

  static PacketSource _packetSourceFor(ConnectionType t) => switch (t) {
    ConnectionType.aprsIs => PacketSource.aprsIs,
    ConnectionType.bleTnc => PacketSource.bleTnc,
    ConnectionType.serialTnc => PacketSource.serialTnc,
  };

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
  ///
  /// [digipeaterPath] overrides the default digipeater aliases when the
  /// effective connection is RF (BLE or Serial). APRS-IS connections ignore
  /// this. Used by v0.17 group-message / bulletin send.
  ///
  /// No-op when the user is unlicensed — TX is unconditionally blocked.
  Future<void> sendLine(
    String aprsLine, {
    ConnectionType? forceVia,
    List<String>? digipeaterPath,
  }) async {
    if (!_settings.isLicensed) {
      debugPrint('[TxService] TX rejected: unlicensed mode');
      return;
    }
    final conn = _effectiveConnection(forceVia: forceVia);
    if (conn == null) return;
    await conn.sendLine(aprsLine, digipeaterPath: digipeaterPath);
    onSent?.call(aprsLine, _packetSourceFor(conn.type));
  }

  /// Send a bulletin packet honoring the per-bulletin transport flags. Unlike
  /// [sendLine], this does *not* use the Serial > BLE > APRS-IS hierarchy —
  /// bulletins can independently go via RF, APRS-IS, or both, per the user's
  /// `viaRf` / `viaAprsIs` settings on each `OutgoingBulletin` (ADR-057).
  ///
  /// When [viaRf] is true, the first live TNC (Serial preferred over BLE)
  /// receives the line with [rfPath] as the digipeater path. When [viaAprsIs]
  /// is true, the APRS-IS connection receives the line (paths ignored). If
  /// both are true and both are connected, the line goes to both.
  Future<void> sendBulletin(
    String aprsLine, {
    required bool viaRf,
    required bool viaAprsIs,
    List<String>? rfPath,
  }) async {
    if (!_settings.isLicensed) {
      debugPrint('[TxService] bulletin TX rejected: unlicensed mode');
      return;
    }
    if (viaAprsIs) {
      final conn = _registry.all
          .where((c) => c.type == ConnectionType.aprsIs && c.isConnected)
          .firstOrNull;
      if (conn != null) {
        try {
          await conn.sendLine(aprsLine);
          onSent?.call(aprsLine, _packetSourceFor(conn.type));
        } catch (e) {
          debugPrint('TxService: bulletin via APRS-IS failed: $e');
        }
      }
    }
    if (viaRf) {
      final conn = _registry.all
          .where(
            (c) =>
                (c.type == ConnectionType.serialTnc ||
                    c.type == ConnectionType.bleTnc) &&
                c.isConnected,
          )
          .firstOrNull;
      if (conn != null) {
        try {
          await conn.sendLine(aprsLine, digipeaterPath: rfPath);
          onSent?.call(aprsLine, _packetSourceFor(conn.type));
        } catch (e) {
          debugPrint('TxService: bulletin via RF (${conn.id}) failed: $e');
        }
      }
    }
  }

  /// Fan out [aprsLine] to every connection where
  /// [MeridianConnection.beaconingEnabled] is true and the connection is live.
  ///
  /// Each connection is attempted independently — a failure on one does not
  /// block the others.
  ///
  /// No-op when the user is unlicensed — TX is unconditionally blocked.
  Future<void> sendBeacon(String aprsLine) async {
    if (!_settings.isLicensed) {
      debugPrint('[TxService] TX rejected: unlicensed mode');
      return;
    }
    for (final conn in _registry.all) {
      if (conn.beaconingEnabled && conn.isConnected) {
        try {
          await conn.sendLine(aprsLine);
          onSent?.call(aprsLine, _packetSourceFor(conn.type));
        } catch (e) {
          debugPrint('TxService: sendBeacon via ${conn.id} failed: $e');
        }
      }
    }
  }

  /// Send [aprsLine] to the first connected TNC (Serial takes priority over BLE).
  ///
  /// Used by [BackgroundServiceManager] to forward background-isolate IPC
  /// beacon/bulletin requests to the live TNC connection. [digipeaterPath]
  /// overrides the default digipeater aliases (bulletins use WIDE2-2).
  Future<void> sendViaTncOnly(
    String aprsLine, {
    List<String>? digipeaterPath,
  }) async {
    final conn = _registry.all
        .where(
          (c) =>
              (c.type == ConnectionType.serialTnc ||
                  c.type == ConnectionType.bleTnc) &&
              c.isConnected,
        )
        .firstOrNull;
    if (conn != null) {
      await conn.sendLine(aprsLine, digipeaterPath: digipeaterPath);
      onSent?.call(aprsLine, _packetSourceFor(conn.type));
    }
  }

  /// True when any TNC (BLE or Serial) is currently live.
  bool get _tncAvailable => _registry.all.any(
    (c) =>
        (c.type == ConnectionType.bleTnc ||
            c.type == ConnectionType.serialTnc) &&
        c.isConnected,
  );

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
    final tncNowConnected = _tncAvailable;
    if (_tncWasConnected && !tncNowConnected) {
      _eventController.add(TxEventTncDisconnected());
    } else if (!_tncWasConnected && tncNowConnected) {
      _eventController.add(TxEventTncReconnected());
    }
    _tncWasConnected = tncNowConnected;
    notifyListeners();
  }
}
