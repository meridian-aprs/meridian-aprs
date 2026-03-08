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

  @override
  Stream<String> get lines => _controller.stream;

  @override
  Future<void> connect() async {
    _socket = await Socket.connect(host, port);
    _socket!.write(loginLine);
    if (filterLine != null) _socket!.write(filterLine);
    _socket!
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _controller.add,
          onError: _controller.addError,
          onDone: _controller.close,
        );
  }

  @override
  void sendLine(String line) => _socket?.write(line);

  @override
  Future<void> disconnect() async {
    await _socket?.close();
    _socket = null;
  }
}
