import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show debugPrint, kIsWeb, visibleForTesting;

import '../util/clock.dart';
import 'aprs_transport.dart';

// TODO(web): replace with WebSocketTransport — see ADR-004
class AprsIsTransport implements AprsTransport {
  String _host;
  int _port;
  String _loginLine;
  String? _filterLine;

  AprsIsTransport({
    String host = 'rotate.aprs2.net',
    int port = 14580,
    required String loginLine,
    String? filterLine,
    Clock clock = DateTime.now,
  }) : _host = host,
       _port = port,
       _loginLine = loginLine,
       _filterLine = filterLine,
       _clock = clock;

  final Clock _clock;

  String get host => _host;
  int get port => _port;

  /// Updates the server host and port used on the next [connect] call.
  /// Safe to call while disconnected; has no effect on an active connection.
  void updateServer({required String host, required int port}) {
    _host = host;
    _port = port;
  }

  /// Updates the login line used on the next [connect] call.
  /// Safe to call while disconnected; has no effect on an active connection.
  ///
  /// Deliberately does NOT touch the filter line. The filter line carries the
  /// last server-side `#filter …` directive the connection has prepared and
  /// must survive a credential refresh — wiping it on every login update was
  /// the cause of the "no packets until I pan the map" class of bugs (Issue
  /// #84). Use [setFilterLine] to update the filter independently.
  void updateLoginLine(String loginLine) {
    _loginLine = loginLine;
  }

  /// Replace (or clear) the filter line used on the next [connect] call.
  /// Pass `null` to clear; otherwise the value is written verbatim to the
  /// socket immediately after the login line on connect.
  void setFilterLine(String? filterLine) {
    _filterLine = filterLine;
  }

  /// The filter line that will be written to the socket on the next [connect].
  /// Exposed so callers (and tests) can verify the persistent filter survives
  /// credential refreshes.
  String? get filterLine => _filterLine;

  Socket? _socket;
  StreamSubscription? _socketSubscription;

  // Read-side idle watchdog. The server sends keepalive comment lines on its
  // own (`# server-name ...` every ~20 s on aprsc / javAPRSSrvr), so any
  // healthy connection produces inbound bytes well within the timeout window.
  // If nothing arrives for [_readIdleTimeout] we treat the socket as wedged
  // (Issue #76) and tear it down so the normal reconnect path takes over.
  Timer? _readWatchdog;
  static const _readIdleTimeout = Duration(seconds: 120);

  // Wall-clock timestamp of the most recently received line. Null until the
  // server speaks once. Exposed to the foreground service so the FGS-driven
  // heartbeat can detect a wedged socket even if a Dart Timer is throttled
  // by Doze (Issue #76).
  DateTime? _lastLineAt;
  DateTime? get lastLineAt => _lastLineAt;

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
      _socket = await Socket.connect(_host, _port);
      // Socket also implements IOSink, whose .done future completes with the
      // same SocketException when the OS aborts the connection (e.g. Android
      // kills TCP sockets on screen lock). Our stream listener's onError
      // already handles state updates; ignoring .done prevents the same error
      // from also reaching the zone as an unhandled exception.
      _socket!.done.ignore();

      // Disable Nagle so short APRS lines flush immediately, and ask the
      // kernel to send TCP keepalive probes so half-dead sockets surface as
      // an error instead of hanging silently (Issue #76). SO_KEEPALIVE is a
      // best-effort hint — some platforms may not honour it through dart:io.
      _socket!.setOption(SocketOption.tcpNoDelay, true);
      try {
        _socket!.setRawOption(
          RawSocketOption.fromBool(
            RawSocketOption.levelSocket,
            // SO_KEEPALIVE — POSIX socket-level option, value 9 on Linux/Android,
            // 8 on macOS/iOS. dart:io does not expose a portable constant, so
            // try the Linux value (covers Android, the platform this targets)
            // and let setRawOption throw on platforms that disagree — the catch
            // below logs and continues; the read watchdog still covers us.
            9,
            true,
          ),
        );
      } catch (e) {
        debugPrint('AprsIsTransport: SO_KEEPALIVE not honoured: $e');
      }

      _socket!.write(_loginLine);
      if (_filterLine != null) _socket!.write(_filterLine);
      _emitState(ConnectionStatus.connected);
      _resetReadWatchdog();

      _socketSubscription = _socket!
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              _lastLineAt = _clock();
              _resetReadWatchdog();
              if (!_controller.isClosed) _controller.add(line);
            },
            onError: (Object e) {
              // Connection dropped with an error (e.g. ECONNABORTED when the
              // OS kills the socket in the background). Update state and clear
              // the dead socket reference so that subsequent sendLine() calls
              // are no-ops rather than throwing on the dead socket. Do NOT
              // propagate the error onto _controller — unhandled broadcast
              // errors crash the app. The caller observes the state change.
              _cancelReadWatchdog();
              _socket = null;
              _socketSubscription = null;
              _emitState(ConnectionStatus.disconnected);
            },
            onDone: () {
              _cancelReadWatchdog();
              _socket = null;
              _socketSubscription = null;
              _emitState(ConnectionStatus.disconnected);
            },
            cancelOnError: true,
          );
    } catch (e) {
      _cancelReadWatchdog();
      _emitState(ConnectionStatus.disconnected);
      rethrow;
    }
  }

  void _resetReadWatchdog() {
    _readWatchdog?.cancel();
    _readWatchdog = Timer(_readIdleTimeout, _onReadIdleTimeout);
  }

  void _cancelReadWatchdog() {
    _readWatchdog?.cancel();
    _readWatchdog = null;
  }

  void _onReadIdleTimeout() {
    debugPrint(
      'AprsIsTransport: read watchdog fired (no bytes for '
      '${_readIdleTimeout.inSeconds}s) — destroying socket. '
      'lastLineAt=$_lastLineAt now=${DateTime.now()}',
    );
    // destroy() releases the socket forcibly; the listener's onError/onDone
    // path then runs through normal disconnected-state bookkeeping. If the
    // OS swallows the close silently, the foreground service heartbeat in
    // BackgroundServiceManager will catch the staleness on the next tick
    // and call recycle() on the connection.
    _socket?.destroy();
    // Belt-and-suspenders: emit disconnected immediately so the rest of the
    // app stops trusting this transport even if the listener never fires.
    _socket = null;
    _emitState(ConnectionStatus.disconnected);
  }

  /// Force a hard reset of the underlying socket. Used by external watchdogs
  /// (foreground-service heartbeat) that have detected staleness via
  /// [lastLineAt] but cannot rely on the in-isolate Dart Timer to have fired
  /// under Android Doze. Safe no-op if there is no live socket.
  Future<void> forceReset() async {
    debugPrint(
      'AprsIsTransport: forceReset called by external watchdog — '
      'lastLineAt=$_lastLineAt',
    );
    _cancelReadWatchdog();
    final s = _socket;
    _socket = null;
    s?.destroy();
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    _emitState(ConnectionStatus.disconnected);
  }

  /// Test hook — fire the idle watchdog handler immediately so unit tests can
  /// assert the disconnect/reconnect contract without waiting on real time.
  @visibleForTesting
  void debugFireReadWatchdog() => _onReadIdleTimeout();

  /// Test hook — true if the read watchdog timer is currently armed.
  @visibleForTesting
  bool get debugReadWatchdogActive => _readWatchdog?.isActive ?? false;

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
    _cancelReadWatchdog();
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
