import 'dart:async';

/// The lifecycle state of a transport connection.
enum ConnectionStatus { disconnected, connecting, connected }

abstract class AprsTransport {
  /// Raw APRS-IS lines, newline stripped. Comment lines included.
  Stream<String> get lines;

  /// Emits the current [ConnectionStatus] whenever it changes.
  Stream<ConnectionStatus> get connectionState;

  Future<void> connect();
  Future<void> disconnect();

  /// Send a raw line to the server (e.g. a new #filter command).
  void sendLine(String line);
}
