import 'dart:async';

import 'package:flutter/foundation.dart';

import '../transport/aprs_transport.dart' show ConnectionStatus;

/// Shared retry/backoff logic for connections that support automatic reconnect.
///
/// Mix this into a [MeridianConnection] implementation to get:
///   - Exponential backoff (2 s → 4 s → 8 s → 16 s → 30 s) up to
///     [_maxRetries] fast attempts.
///   - After fast retries are exhausted, [enterWaitingPhase] is called.
///     The default implementation retries via [doAttemptReconnect]; subclasses
///     can override (e.g. [BleConnection] invokes OS background scanning).
///   - [cancelReconnect] tears down all pending state cleanly.
///
/// The mixing class is responsible for calling [notifyListeners] and emitting
/// [ConnectionStatus] events to its stream; this mixin only drives the timer
/// and calls the abstract [doAttemptReconnect].
///
/// Typical usage:
/// ```dart
/// class BleConnection extends MeridianConnection with ReconnectableMixin {
///   @override
///   Future<void> doAttemptReconnect() async { ... }
/// }
/// ```
mixin ReconnectableMixin {
  // ---------------------------------------------------------------------------
  // Parameters (override in tests or subclasses via assignments in setUp)
  // ---------------------------------------------------------------------------

  static const int _maxRetries = 5;
  static const Duration _baseRetryDelay = Duration(seconds: 2);
  static const Duration _maxRetryDelay = Duration(seconds: 30);

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  int _retryAttempt = 0;
  Timer? _retryTimer;

  /// True while waiting for the OS to surface the device (post-fast-retries).
  bool _inWaitingPhase = false;

  /// True once the connection has successfully connected at least once in this
  /// session. Reconnect is only attempted after the first successful connect.
  bool _sessionEverConnected = false;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Whether OS-managed background reconnect is in progress.
  bool get isInWaitingPhase => _inWaitingPhase;

  /// Whether a fast-retry timer is pending.
  bool get hasScheduledRetry => _retryTimer != null;

  /// Mark this session as having connected at least once.
  ///
  /// Call from the connection's status listener when [ConnectionStatus.connected]
  /// is received. Enables reconnect on subsequent disconnects.
  void markSessionConnected() {
    _sessionEverConnected = true;
    _retryAttempt = 0;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// Determine whether reconnect should be attempted after an error.
  ///
  /// Returns true when a session has been established at least once and a
  /// reconnect is not already scheduled or in progress.
  bool shouldAttemptReconnect() =>
      _sessionEverConnected && _retryTimer == null && !_inWaitingPhase;

  /// Schedule a reconnect attempt after the next backoff delay.
  ///
  /// Emits [ConnectionStatus.reconnecting] via [onReconnectStatus] so callers
  /// can update their state stream. Does nothing if retries are already in
  /// progress.
  void scheduleReconnect(void Function(ConnectionStatus) onReconnectStatus) {
    if (_retryTimer != null || _inWaitingPhase) return;

    if (_retryAttempt >= _maxRetries) {
      debugPrint(
        'ReconnectableMixin: fast retries exhausted — entering waiting phase',
      );
      enterWaitingPhase(onReconnectStatus);
      return;
    }

    _retryAttempt++;
    final delay = _retryDelay(_retryAttempt);
    debugPrint(
      'ReconnectableMixin: scheduling reconnect attempt '
      '$_retryAttempt/$_maxRetries in ${delay.inSeconds}s',
    );
    onReconnectStatus(ConnectionStatus.reconnecting);
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      doAttemptReconnect();
    });
  }

  /// Cancel all pending retry timers and reset backoff state.
  ///
  /// Call from [disconnect] to abort any in-progress reconnect sequence.
  void cancelReconnect() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryAttempt = 0;
    _inWaitingPhase = false;
    _sessionEverConnected = false;
  }

  /// Called when fast retries are exhausted.
  ///
  /// Emits [ConnectionStatus.waitingForDevice] then calls
  /// [doWaitingPhaseReconnect]. Override [doWaitingPhaseReconnect] (not this
  /// method) to change reconnect behaviour in the waiting phase — e.g.
  /// [BleConnection] uses OS background scanning instead of active polling.
  @protected
  void enterWaitingPhase(void Function(ConnectionStatus) onReconnectStatus) {
    _inWaitingPhase = true;
    _retryAttempt = 0;
    onReconnectStatus(ConnectionStatus.waitingForDevice);
    doWaitingPhaseReconnect();
  }

  /// Perform the waiting-phase reconnect attempt.
  ///
  /// Default: delegates to [doAttemptReconnect] (active reconnect).
  /// Override in subclasses that support OS-managed background scanning.
  @protected
  Future<void> doWaitingPhaseReconnect() => doAttemptReconnect();

  /// Perform a single reconnect attempt.
  ///
  /// Implementations should tear down the dead transport, create a fresh one,
  /// and call [connect]. If [connect] succeeds, [markSessionConnected] will
  /// be called by the status listener. If it fails, the status listener will
  /// trigger another [scheduleReconnect].
  @protected
  Future<void> doAttemptReconnect();

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  Duration _retryDelay(int attempt) {
    final ms = _baseRetryDelay.inMilliseconds * (1 << (attempt - 1));
    return Duration(milliseconds: ms.clamp(0, _maxRetryDelay.inMilliseconds));
  }
}
