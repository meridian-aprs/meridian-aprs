import 'dart:async';

/// The lifecycle state of a transport connection.
enum ConnectionStatus {
  disconnected,
  connecting,
  connected,

  /// Fast exponential-backoff retries are in progress.
  reconnecting,

  /// Retries exhausted; waiting for the OS to report the device back in range.
  waitingForDevice,
  error,
}

abstract class AprsTransport {
  /// Raw APRS-IS lines, newline stripped. Comment lines included.
  Stream<String> get lines;

  /// Emits the current [ConnectionStatus] whenever it changes.
  Stream<ConnectionStatus> get connectionState;

  /// Returns the most-recently-set [ConnectionStatus] synchronously.
  /// Allows late subscribers to read the current state without waiting for
  /// the next stream event.
  ConnectionStatus get currentStatus;

  Future<void> connect();
  Future<void> disconnect();

  /// Permanently release all resources (stream controllers, subscriptions).
  /// Call only when the owning service is being destroyed.
  /// Default implementation delegates to [disconnect].
  Future<void> dispose() => disconnect();

  /// Send a raw line to the server (e.g. a new #filter command).
  void sendLine(String line);
}
