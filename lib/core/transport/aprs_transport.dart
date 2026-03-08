import 'dart:async';

abstract class AprsTransport {
  /// Raw APRS-IS lines, newline stripped. Comment lines included.
  Stream<String> get lines;
  Future<void> connect();
  Future<void> disconnect();

  /// Send a raw line to the server (e.g. a new #filter command).
  void sendLine(String line);
}
