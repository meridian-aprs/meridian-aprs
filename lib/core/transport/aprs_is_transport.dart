import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'aprs_transport.dart';

// TODO(web): replace with WebSocketTransport — see ADR-004
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
  StreamSubscription? _socketSubscription;

  // These controllers live for the lifetime of the transport instance — they
  // are never closed by a connection drop, only by an explicit dispose().
  final _controller = StreamController<String>.broadcast();
  final _stateController = StreamController<ConnectionStatus>.broadcast();
  ConnectionStatus _currentStatus = ConnectionStatus.disconnected;

  @override
  Stream<String> get lines => _controller.stream;

  @override
  Stream<ConnectionStatus> get connectionState => _stateController.stream;

  @override
  ConnectionStatus get currentStatus => _currentStatus;

  // Emit a state change, guarded so it is safe to call after dispose().
  void _emitState(ConnectionStatus s) {
    _currentStatus = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }

  @override
  Future<void> connect() async {
    assert(
      !kIsWeb,
      'AprsIsTransport uses dart:io and cannot run on web. '
      'Implement WebSocketTransport per ADR-004.',
    );

    // Cancel any in-flight subscription from a previous connect() call.
    await _socketSubscription?.cancel();
    _socketSubscription = null;

    _emitState(ConnectionStatus.connecting);
    try {
      _socket = await Socket.connect(host, port);
      _socket!.write(loginLine);
      if (filterLine != null) _socket!.write(filterLine);
      _emitState(ConnectionStatus.connected);

      _socketSubscription = _socket!
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (!_controller.isClosed) _controller.add(line);
            },
            onError: (Object e) {
              // Connection dropped with an error. Update state; do NOT
              // propagate the error onto _controller — unhandled broadcast
              // errors crash the app. The caller observes the state change.
              _emitState(ConnectionStatus.disconnected);
            },
            onDone: () {
              _emitState(ConnectionStatus.disconnected);
            },
            cancelOnError: true,
          );
    } catch (e) {
      _emitState(ConnectionStatus.disconnected);
      rethrow;
    }
  }

  @override
  void sendLine(String line) => _socket?.write(line);

  @override
  Future<void> disconnect() async {
    // Cancel the subscription before closing the socket so that onDone /
    // onError callbacks do not fire after we have already updated state here.
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    await _socket?.close();
    _socket = null;
    _emitState(ConnectionStatus.disconnected);
  }

  /// Permanently shut down this transport and release all resources.
  /// Call this only when the owning service is being destroyed.
  @override
  Future<void> dispose() async {
    await disconnect();
    await _controller.close();
    await _stateController.close();
  }
}
