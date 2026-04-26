/// Stateful smart-beaconing scheduler used by the Android background isolate
/// (see `MeridianConnectionTask`). Wraps the pure-function [SmartBeaconing]
/// math with the speed/heading state that decisions depend on, in a form that
/// is testable without spinning up a `flutter_foreground_task` TaskHandler.
///
/// The foreground [BeaconingService] keeps equivalent state inline; this
/// helper exists so the background isolate can reuse the same semantics
/// (turn-triggered immediate beacons, only-shorten reschedules, post-turn
/// heading reset) without duplicating the math in two places.
library;

import 'package:geolocator/geolocator.dart';

import '../util/clock.dart';
import 'smart_beaconing.dart';

/// Decision returned by [SmartBeaconScheduler.onPositionUpdate].
sealed class SmartAction {
  const SmartAction();
}

/// Fire a beacon immediately. The caller must cancel any pending timer and
/// call [SmartBeaconScheduler.markBeaconSent] once the beacon is on its way.
class FireNow extends SmartAction {
  const FireNow();
}

/// Cancel the current timer and reschedule it for [delay] from now.
/// Only emitted when the new interval would fire sooner than the existing
/// timer — never used to push a beacon further out.
class Reschedule extends SmartAction {
  const Reschedule(this.delay);
  final Duration delay;
}

/// No change to the current timer.
class Keep extends SmartAction {
  const Keep();
}

class SmartBeaconScheduler {
  SmartBeaconScheduler({
    required SmartBeaconingParams params,
    Clock clock = DateTime.now,
  }) : _params = params,
       _clock = clock;

  SmartBeaconingParams _params;
  final Clock _clock;
  Position? _lastPosition;
  double? _lastHeading;
  DateTime? _lastBeaconAt;
  DateTime? _currentTimerStartedAt;
  int? _currentTimerIntervalS;

  /// Hot-reload tunable params (e.g. when the user changes them in Settings
  /// while the background service is running).
  void updateParams(SmartBeaconingParams params) {
    _params = params;
  }

  /// Record that a beacon was just transmitted. Resets the turn-trigger window.
  void markBeaconSent(DateTime ts) {
    _lastBeaconAt = ts;
  }

  /// Seed the "current timer" bookkeeping when the caller schedules a timer
  /// from a known start time other than `now` — e.g. when resuming after the
  /// foreground fired the last beacon at `lastBeaconTs` and the background
  /// timer is set to fire at `lastBeaconTs + intervalS`.
  ///
  /// Maintains the invariant `startedAt + intervalS == fire time` so that
  /// later [onPositionUpdate] calls compute remaining time correctly.
  void seedCurrentTimer({required DateTime startedAt, required int intervalS}) {
    _currentTimerStartedAt = startedAt;
    _currentTimerIntervalS = intervalS;
  }

  /// Compute the interval the caller should use to schedule the next beacon
  /// timer (typically called immediately after a beacon fires). Stores the
  /// deadline so future [onPositionUpdate] calls can decide whether to
  /// shorten it.
  ///
  /// If no GPS fix is available yet, falls back to the slowRate.
  Duration intervalAfterBeacon({DateTime? now}) {
    final stamp = now ?? _clock();
    final speedKmh = _speedKmhFromLast();
    final intervalS = SmartBeaconing.computeInterval(_params, speedKmh);
    _currentTimerStartedAt = stamp;
    _currentTimerIntervalS = intervalS;
    return Duration(seconds: intervalS);
  }

  /// Process a new GPS [position]. Returns the action the caller should take.
  ///
  /// Mirrors [BeaconingService._onPositionUpdate] exactly — turn trigger
  /// check first (gated on minTurnTimeS), then only-shorten reschedule.
  SmartAction onPositionUpdate(Position position, {DateTime? now}) {
    final stamp = now ?? _clock();
    final speedKmh = (position.speed * 3.6).clamp(0.0, double.infinity);
    final heading = position.heading;

    if (_lastPosition != null &&
        _lastBeaconAt != null &&
        _lastHeading != null) {
      final headingDelta = _angleDiff(heading, _lastHeading!);
      final timeSinceLast = stamp.difference(_lastBeaconAt!);
      if (SmartBeaconing.shouldTriggerTurn(
        _params,
        speedKmh,
        headingDelta,
        timeSinceLast,
      )) {
        // Reset heading to current pre-fire so the next delta is measured
        // from the post-turn heading, not the pre-turn one.
        _lastHeading = heading;
        _lastPosition = position;
        return const FireNow();
      }
    }

    _lastHeading = heading;
    _lastPosition = position;

    if (_currentTimerStartedAt != null && _currentTimerIntervalS != null) {
      final newIntervalS = SmartBeaconing.computeInterval(_params, speedKmh);
      final elapsed = stamp.difference(_currentTimerStartedAt!).inSeconds;
      final remaining = _currentTimerIntervalS! - elapsed;
      // Only shorten — never push the beacon further out.
      if (newIntervalS < remaining) {
        _currentTimerStartedAt = stamp;
        _currentTimerIntervalS = newIntervalS;
        return Reschedule(Duration(seconds: newIntervalS));
      }
    }

    return const Keep();
  }

  double _speedKmhFromLast() {
    final last = _lastPosition;
    if (last == null) return 0.0;
    return (last.speed * 3.6).clamp(0.0, double.infinity);
  }

  /// Absolute angular difference in [0, 180].
  static double _angleDiff(double a, double b) {
    final diff = (a - b).abs() % 360;
    return diff > 180 ? 360 - diff : diff;
  }
}
