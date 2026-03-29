/// Global TX transport router.
///
/// Routes outgoing APRS packets (beacons and messages) to either APRS-IS or a
/// connected TNC. Exposes [TxTransportPref] persistence with auto-resolution
/// and banner events for TNC connect/disconnect transitions.
///
/// Preference semantics:
/// - [TxTransportPref.auto]: use TNC when connected, APRS-IS otherwise.
/// - [TxTransportPref.aprsIs]: always use APRS-IS.
/// - [TxTransportPref.tnc]: use TNC; falls back to APRS-IS when TNC
///   disconnects but does NOT persist the fallback as the stored preference.
///
/// See ADR-023 in docs/DECISIONS.md for rationale behind a global (not
/// per-station) TX transport preference.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/ax25/ax25_encoder.dart';
import '../core/transport/aprs_transport.dart'
    show AprsTransport, ConnectionStatus;
import 'tnc_service.dart' show TncService;

/// Whether the user wants to send via APRS-IS, TNC, or let the app decide.
enum TxTransportPref { auto, aprsIs, tnc }

/// Events emitted by [TxService] to drive banner UI.
sealed class TxEvent {}

/// TNC disconnected while RF was the active TX path.
class TxEventTncDisconnected extends TxEvent {}

/// TNC reconnected — offer to switch back to RF.
class TxEventTncReconnected extends TxEvent {}

class TxService extends ChangeNotifier {
  TxService(this._aprsIs, this._tnc) {
    _tnc.connectionState.listen(_onTncConnectionState);
    _aprsIs.connectionState.listen((_) => notifyListeners());
  }

  final AprsTransport _aprsIs;
  final TncService _tnc;

  static const _keyPref = 'tx_transport_pref';
  static const _keyExplicit = 'tx_pref_explicit';

  TxTransportPref _preference = TxTransportPref.auto;
  bool _userHasExplicitlySet = false;

  final _eventController = StreamController<TxEvent>.broadcast();

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// The stored preference (may be [TxTransportPref.auto]).
  TxTransportPref get preference => _preference;

  /// Whether the user has explicitly chosen a transport (vs default/auto).
  bool get userHasExplicitlySet => _userHasExplicitlySet;

  /// Whether APRS-IS is currently connected and available for TX.
  bool get aprsIsAvailable =>
      _aprsIs.currentStatus == ConnectionStatus.connected;

  /// Whether a TNC is currently connected and available for TX.
  bool get tncAvailable => _tnc.transportManager.isConnected;

  /// Resolved effective transport (never auto).
  TxTransportPref get effective {
    if (_preference == TxTransportPref.auto) {
      return tncAvailable ? TxTransportPref.tnc : TxTransportPref.aprsIs;
    }
    if (_preference == TxTransportPref.tnc && !tncAvailable) {
      return TxTransportPref.aprsIs;
    }
    return _preference;
  }

  /// Stream of [TxEvent]s for UI banner display.
  Stream<TxEvent> get events => _eventController.stream;

  /// Persist and apply a TX transport preference.
  ///
  /// [explicit] should be true when the user actively chose the transport in
  /// the UI. Set false for programmatic/auto changes that should not persist.
  Future<void> setPreference(
    TxTransportPref pref, {
    bool explicit = true,
  }) async {
    _preference = pref;
    if (explicit) _userHasExplicitlySet = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyPref, pref.index);
    if (explicit) await prefs.setBool(_keyExplicit, true);
  }

  /// Load persisted preference. Call once during app startup.
  Future<void> loadPersistedPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt(_keyPref);
    if (idx != null && idx < TxTransportPref.values.length) {
      _preference = TxTransportPref.values[idx];
    }
    _userHasExplicitlySet = prefs.getBool(_keyExplicit) ?? false;
    notifyListeners();
  }

  /// Send an APRS packet via the effective transport.
  ///
  /// [aprsLine] is the full APRS-IS formatted string, e.g.:
  /// `W1AW-9>APZMDN,TCPIP*:!4903.50N/07201.75W>Comment`
  ///
  /// When routing to the TNC, the header is parsed to extract the source
  /// callsign and info field; an AX.25 UI frame is constructed and sent
  /// with a standard WIDE1-1,WIDE2-1 path.
  Future<void> sendLine(String aprsLine) async {
    if (effective == TxTransportPref.tnc) {
      await _sendViaTnc(aprsLine);
    } else {
      _aprsIs.sendLine('$aprsLine\r\n');
    }
  }

  @override
  void dispose() {
    _eventController.close();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Internal — TNC TX
  // ---------------------------------------------------------------------------

  Future<void> _sendViaTnc(String aprsLine) async {
    final transport = _tnc.transportManager.activeTransport;
    if (transport == null || !transport.isConnected) {
      // Silently fall back to APRS-IS if TNC not ready.
      _aprsIs.sendLine('$aprsLine\r\n');
      return;
    }

    final ax25Bytes = _buildAx25Bytes(aprsLine);
    if (ax25Bytes != null) {
      await transport.sendFrame(ax25Bytes);
    }
  }

  /// Parse an APRS-IS line and encode it as raw AX.25 bytes.
  ///
  /// Returns null if the line cannot be parsed (header malformed).
  Uint8List? _buildAx25Bytes(String aprsLine) {
    // Format: "SOURCE>DEST,PATH:INFO"
    final gtIdx = aprsLine.indexOf('>');
    final colonIdx = aprsLine.indexOf(':');
    if (gtIdx < 0 || colonIdx < 0 || colonIdx <= gtIdx) return null;

    final sourceRaw = aprsLine.substring(0, gtIdx).trim();
    final infoField = aprsLine.substring(colonIdx + 1);

    // Split callsign and SSID from source.
    final sourceParts = sourceRaw.split('-');
    final callsign = sourceParts[0].toUpperCase();
    final ssid = sourceParts.length > 1 ? int.tryParse(sourceParts[1]) ?? 0 : 0;

    final frame = Ax25Encoder.buildAprsFrame(
      sourceCallsign: callsign,
      sourceSsid: ssid,
      infoField: infoField,
    );
    return Ax25Encoder.encodeUiFrame(frame);
  }

  // ---------------------------------------------------------------------------
  // Internal — TNC state tracking
  // ---------------------------------------------------------------------------

  bool _tncWasConnected = false;

  void _onTncConnectionState(ConnectionStatus status) {
    final nowConnected = status == ConnectionStatus.connected;

    if (_tncWasConnected && !nowConnected) {
      // TNC just disconnected — notify when auto/tnc since effective falls back
      // to APRS-IS and the user should know.
      if (_preference == TxTransportPref.tnc ||
          _preference == TxTransportPref.auto) {
        _eventController.add(TxEventTncDisconnected());
      }
    } else if (!_tncWasConnected && nowConnected) {
      // TNC just connected — only prompt when the user is explicitly on APRS-IS.
      // For auto/tnc preferences there is nothing to decide: auto already picks
      // RF automatically, and tnc preference means RF is already intended.
      if (_preference == TxTransportPref.aprsIs) {
        _eventController.add(TxEventTncReconnected());
      }
    }

    _tncWasConnected = nowConnected;
    notifyListeners();
  }
}
