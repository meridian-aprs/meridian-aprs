import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'aprs_transport.dart';

class AprsIsTransport implements AprsTransport {
  final String host;
  final int port;
  final String loginLine;
  final String? filterLine;

  AprsIsTransport({
    this.host = 'rotate.aprs2.net',
    this.port = 14580,
    required this.loginLine,
    this.filterLine,
  });

  Socket? _socket;
  final _controller = StreamController<String>.broadcast();
  final _stateController = StreamController<ConnectionStatus>.broadcast();
  ConnectionStatus _currentStatus = ConnectionStatus.disconnected;

  @override
  Stream<String> get lines => _controller.stream;

  @override
  Stream<ConnectionStatus> get connectionState => _stateController.stream;

  @override
  ConnectionStatus get currentStatus => _currentStatus;

  @override
  Future<void> connect() async {
    _currentStatus = ConnectionStatus.connecting;
    _stateController.add(ConnectionStatus.connecting);
    try {
      _socket = await Socket.connect(host, port);
      _socket!.write(loginLine);
      if (filterLine != null) _socket!.write(filterLine);
      _currentStatus = ConnectionStatus.connected;
      _stateController.add(ConnectionStatus.connected);
      _socket!
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _controller.add,
            onError: (e) {
              _currentStatus = ConnectionStatus.disconnected;
              _stateController.add(ConnectionStatus.disconnected);
              _controller.addError(e);
            },
            onDone: () {
              _currentStatus = ConnectionStatus.disconnected;
              _stateController.add(ConnectionStatus.disconnected);
              _controller.close();
            },
          );
    } catch (e) {
      _currentStatus = ConnectionStatus.disconnected;
      _stateController.add(ConnectionStatus.disconnected);
      rethrow;
    }
  }

  @override
  void sendLine(String line) => _socket?.write(line);

  @override
  Future<void> disconnect() async {
    await _socket?.close();
    _socket = null;
    await _stateController.close();
  }
}
