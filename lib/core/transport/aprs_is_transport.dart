import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'aprs_transport.dart';

// TODO(web): replace with WebSocketTransport — see ADR-004
class AprsIsTransport implements AprsTransport {
  final String host;
  final int port;
  String _loginLine;
  String? _filterLine;

  AprsIsTransport({
    this.host = 'rotate.aprs2.net',
    this.port = 14580,
    required String loginLine,
    String? filterLine,
  }) : _loginLine = loginLine,
       _filterLine = filterLine;

  /// Updates the login and filter lines used on the next [connect] call.
  /// Safe to call while disconnected; has no effect on an active connection.
  void updateCredentials({required String loginLine, String? filterLine}) {
    _loginLine = loginLine;
    _filterLine = filterLine;
  }

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
      // Socket also implements IOSink, whose .done future completes with the
      // same SocketException when the OS aborts the connection (e.g. Android
      // kills TCP sockets on screen lock). Our stream listener's onError
      // already handles state updates; ignoring .done prevents the same error
      // from also reaching the zone as an unhandled exception.
      _socket!.done.ignore();
      _socket!.write(_loginLine);
      if (_filterLine != null) _socket!.write(_filterLine);
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
              // Connection dropped with an error (e.g. ECONNABORTED when the
              // OS kills the socket in the background). Update state and clear
              // the dead socket reference so that subsequent sendLine() calls
              // are no-ops rather than throwing on the dead socket. Do NOT
              // propagate the error onto _controller — unhandled broadcast
              // errors crash the app. The caller observes the state change.
              _socket = null;
              _socketSubscription = null;
              _emitState(ConnectionStatus.disconnected);
            },
            onDone: () {
              _socket = null;
              _socketSubscription = null;
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
  void sendLine(String line) {
    try {
      _socket?.write(line);
    } on SocketException {
      // Socket died between the null-check and the write (race between OS
      // abort and our null-out in onError). Safe to discard — the onError
      // handler will fire separately and update the connection state.
    }
  }

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
