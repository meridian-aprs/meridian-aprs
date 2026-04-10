import 'dart:async';
import 'dart:typed_data';

import 'aprs_transport.dart' show ConnectionStatus;

/// Low-level KISS TNC transport abstraction.
///
/// Emits raw AX.25 frame payloads (KISS header stripped) on [frameStream].
/// Both [SerialKissTransport] and [BleTncTransport] implement this interface.
///
/// Parsing (AX.25 → APRS text) is the responsibility of the service layer,
/// not the transport. This keeps the transport layer free of APRS semantics
/// and testable at the raw byte level.
abstract class KissTncTransport {
  /// Stream of decoded KISS frames as raw AX.25 byte arrays.
  ///
  /// Each emission is a complete AX.25 frame payload (command byte stripped).
  Stream<Uint8List> get frameStream;

  /// Emits the current [ConnectionStatus] whenever it changes.
  Stream<ConnectionStatus> get connectionState;

  /// Returns the most-recently-set [ConnectionStatus] synchronously.
  ConnectionStatus get currentStatus;

  /// True when the transport is connected and ready to receive/send frames.
  bool get isConnected;

  /// Connect to the TNC. Throws on failure.
  Future<void> connect();

  /// Connect using OS-managed background scanning.
  ///
  /// Default implementation delegates to [connect]. BLE transports override
  /// this to pass [autoConnect: true] to the platform, letting the OS
  /// reconnect when the device comes back in range without active polling.
  Future<void> connectBackground() => connect();

  /// Disconnect cleanly and release all resources.
  Future<void> disconnect();

  /// Send a raw AX.25 frame wrapped in a KISS frame.
  ///
  /// The transport is responsible for KISS-encoding [ax25Frame] before
  /// transmitting. Throws if not connected.
  Future<void> sendFrame(Uint8List ax25Frame);
}
