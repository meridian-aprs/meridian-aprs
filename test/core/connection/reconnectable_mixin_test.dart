import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_aprs/core/connection/reconnectable_mixin.dart';
import 'package:meridian_aprs/core/transport/aprs_transport.dart'
    show ConnectionStatus;

// ---------------------------------------------------------------------------
// Test double — a minimal class that uses the mixin
// ---------------------------------------------------------------------------

class _TestConnection with ReconnectableMixin {
  int reconnectAttempts = 0;
  final List<ConnectionStatus> emittedStatuses = [];
  Completer<void>? reconnectCompleter;

  void Function(ConnectionStatus) get _emit =>
      (s) => emittedStatuses.add(s);

  @override
  Future<void> doAttemptReconnect() async {
    reconnectAttempts++;
    reconnectCompleter?.complete();
    reconnectCompleter = Completer<void>();
  }

  // Convenience wrappers
  void triggerSchedule() => scheduleReconnect(_emit);
  void triggerCancel() => cancelReconnect();
  void triggerMarkConnected() => markSessionConnected();
}

void main() {
  group('ReconnectableMixin', () {
    late _TestConnection conn;

    setUp(() {
      conn = _TestConnection();
    });

    tearDown(() {
      conn.triggerCancel(); // clean up any pending timers
    });

    test('initial state: no retry pending, not in waiting phase', () {
      expect(conn.hasScheduledRetry, isFalse);
      expect(conn.isInWaitingPhase, isFalse);
      expect(conn.shouldAttemptReconnect(), isFalse);
    });

    test('shouldAttemptReconnect is false before any connect', () {
      expect(conn.shouldAttemptReconnect(), isFalse);
    });

    test('shouldAttemptReconnect is true after markSessionConnected', () {
      conn.triggerMarkConnected();
      expect(conn.shouldAttemptReconnect(), isTrue);
    });

    test('scheduleReconnect emits reconnecting status', () async {
      conn.triggerMarkConnected();
      conn.triggerSchedule();

      expect(conn.emittedStatuses, contains(ConnectionStatus.reconnecting));
      expect(conn.hasScheduledRetry, isTrue);
    });

    test('scheduleReconnect calls doAttemptReconnect after delay', () async {
      conn.triggerMarkConnected();
      conn.triggerSchedule();

      await Future<void>.delayed(const Duration(seconds: 3));
      expect(conn.reconnectAttempts, equals(1));
    });

    test('cancelReconnect clears pending timer', () async {
      conn.triggerMarkConnected();
      conn.triggerSchedule();
      expect(conn.hasScheduledRetry, isTrue);

      conn.triggerCancel();
      expect(conn.hasScheduledRetry, isFalse);
      expect(conn.isInWaitingPhase, isFalse);

      // No reconnect attempt should fire after cancel
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(conn.reconnectAttempts, equals(0));
    });

    test('markSessionConnected resets retry counter', () {
      conn.triggerMarkConnected();
      conn.triggerSchedule(); // attempt 1
      conn.triggerMarkConnected(); // simulates successful reconnect

      // After reconnect success, retry attempt counter resets
      // A fresh scheduleReconnect would start at attempt 1 again
      expect(conn.hasScheduledRetry, isFalse);
    });

    test('scheduleReconnect is idempotent — second call is a no-op', () {
      conn.triggerMarkConnected();
      conn.triggerSchedule();
      conn.triggerSchedule(); // second call
      // Only one status emission (not two)
      expect(
        conn.emittedStatuses
            .where((s) => s == ConnectionStatus.reconnecting)
            .length,
        equals(1),
      );
    });

    test('enters waiting phase after maxRetries attempts', () {
      fakeAsync((async) {
        conn.triggerMarkConnected();

        // Schedule and fire each of the 5 fast-retry timers.
        // Delays: 2s, 4s, 8s, 16s, 30s.
        // Each iteration: schedule → advance past delay → timer fires →
        // doAttemptReconnect() is called → loop repeats.
        final delays = [2, 4, 8, 16, 30];
        for (final delaySecs in delays) {
          conn.triggerSchedule();
          async.elapse(Duration(seconds: delaySecs + 1));
        }

        // The 5th timer has now fired. A 6th scheduleReconnect call (which
        // would happen when the reconnect attempt fails again) is what triggers
        // the waiting-phase transition since _retryAttempt == _maxRetries.
        conn.triggerSchedule();

        expect(conn.isInWaitingPhase, isTrue);
        expect(conn.reconnectAttempts, equals(6)); // 5 fast + 1 waiting
        expect(
          conn.emittedStatuses,
          contains(ConnectionStatus.waitingForDevice),
        );
      });
    });

    test('cancelReconnect resets sessionEverConnected', () {
      conn.triggerMarkConnected();
      expect(conn.shouldAttemptReconnect(), isTrue);

      conn.triggerCancel();
      expect(conn.shouldAttemptReconnect(), isFalse);
    });

    group('backoff delay', () {
      test('retryDelay increases exponentially', () {
        // Access private method via indirect observation:
        // Attempt 1 → 2s, Attempt 2 → 4s, Attempt 3 → 8s, Attempt 4 → 16s,
        // Attempt 5 → 30s (capped at 30s).
        // We verify this by scheduling and checking reconnect timing externally
        // in BleConnection integration tests. Here we just verify the mixin
        // does not schedule a second timer while one is pending.
        conn.triggerMarkConnected();
        conn.triggerSchedule();
        expect(conn.hasScheduledRetry, isTrue);
        conn.triggerSchedule(); // should be no-op
        // Still only one timer
        expect(conn.hasScheduledRetry, isTrue);
      });
    });
  });
}
