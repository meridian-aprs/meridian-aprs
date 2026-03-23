import 'dart:async';

import 'package:meridian_aprs/core/transport/aprs_transport.dart';

class FakeTransport implements AprsTransport {
  final _lines = StreamController<String>.broadcast();
  final _state = StreamController<ConnectionStatus>.broadcast();

  @override
  Stream<String> get lines => _lines.stream;

  @override
  Stream<ConnectionStatus> get connectionState => _state.stream;

  @override
  ConnectionStatus get currentStatus => ConnectionStatus.disconnected;

  @override
  Future<void> connect() async {
    _state.add(ConnectionStatus.connected);
  }

  @override
  Future<void> disconnect() async {
    _state.add(ConnectionStatus.disconnected);
  }

  @override
  Future<void> dispose() => disconnect();

  @override
  void sendLine(String line) {}
}
