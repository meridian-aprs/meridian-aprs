import 'dart:async';

import 'package:flutter/foundation.dart';

import '../transport/aprs_transport.dart' show ConnectionStatus;

export '../transport/aprs_transport.dart' show ConnectionStatus;

/// The type of a [MeridianConnection].
///
/// Used by the UI layer to dispatch connection-specific form builders and by
/// [StationService] to tag ingested packets with the correct [PacketSource].
enum ConnectionType { aprsIs, bleTnc, serialTnc }

/// Unified abstraction over all APRS transport connections.
///
/// Implementors:
///   - [AprsIsConnection] — APRS-IS TCP (or WebSocket on web)
///   - [BleConnection] — KISS over BLE (Mobilinkd, etc.)
///   - [SerialConnection] — KISS over USB serial
///
/// Each connection independently manages its own lifecycle, normalises data to
/// APRS text lines, and gates platform availability via [isAvailable].
///
/// Register connections in [ConnectionRegistry] at app startup. The UI builds
/// itself from [ConnectionRegistry.available]; checking overall connectivity is
/// `registry.isAnyConnected`.
abstract class MeridianConnection extends ChangeNotifier {
  // ---------------------------------------------------------------------------
  // Identity
  // ---------------------------------------------------------------------------

  /// Stable machine-readable identifier, e.g. `'aprs_is'`, `'ble_tnc'`.
  String get id;

  /// Human-readable label shown in the UI, e.g. `'APRS-IS'`, `'BLE TNC'`.
  String get displayName;

  /// Discriminator for type-specific UI and packet tagging.
  ConnectionType get type;

  // ---------------------------------------------------------------------------
  // Platform availability
  // ---------------------------------------------------------------------------

  /// Whether this connection type is supported on the current platform.
  ///
  /// This is a static platform gate — it does not reflect runtime state.
  /// APRS-IS is available everywhere except web (direct TCP); BLE is
  /// iOS/Android only; Serial is desktop only.
  bool get isAvailable;

  // ---------------------------------------------------------------------------
  // Connection state
  // ---------------------------------------------------------------------------

  /// Current [ConnectionStatus].
  ConnectionStatus get status;

  /// Emits [ConnectionStatus] whenever it changes.
  Stream<ConnectionStatus> get connectionState;

  /// True when [status] == [ConnectionStatus.connected].
  bool get isConnected;

  // ---------------------------------------------------------------------------
  // Beaconing
  // ---------------------------------------------------------------------------

  /// Whether position beacons should be transmitted on this connection.
  ///
  /// Persisted to SharedPreferences. Toggle via [setBeaconingEnabled].
  bool get beaconingEnabled;

  /// Persist and apply a beaconing enable/disable change.
  Future<void> setBeaconingEnabled(bool enabled);

  // ---------------------------------------------------------------------------
  // Data I/O
  // ---------------------------------------------------------------------------

  /// Stream of normalised APRS text lines.
  ///
  /// TNC connections decode AX.25 frames internally; APRS-IS connections emit
  /// lines directly. Comment lines (starting with `#`) are included.
  Stream<String> get lines;

  /// Send an APRS packet via this connection.
  ///
  /// [aprsLine] is the full APRS-IS formatted string, e.g.:
  /// `W1AW-9>APZMDN,TCPIP*:!4903.50N/07201.75W>Comment`
  ///
  /// APRS-IS connections append `\r\n` and write to the TCP socket. TNC
  /// connections encode the line as an AX.25 UI frame and send it as a KISS
  /// frame. Throws if not connected.
  Future<void> sendLine(String aprsLine);

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Establish the connection. Throws on failure.
  Future<void> connect();

  /// Disconnect cleanly and release transport resources.
  ///
  /// The [MeridianConnection] instance remains valid and can be reconnected.
  Future<void> disconnect();

  /// Permanently release all resources including stream controllers.
  ///
  /// Call only when the owning registry is being disposed. After [dispose] the
  /// connection must not be used again.
  @override
  Future<void> dispose();

  /// Load persisted settings (e.g. [beaconingEnabled]) from SharedPreferences.
  ///
  /// Call once per connection during app startup, before [connect].
  Future<void> loadPersistedSettings();
}
