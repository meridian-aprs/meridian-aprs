/// SmartBeaconing™ algorithm — pure Dart, no platform dependencies.
///
/// SmartBeaconing adapts the beacon rate to the station's movement:
/// - Fast-moving stations beacon more frequently.
/// - Slow/stationary stations beacon infrequently.
/// - Sharp turns trigger an immediate beacon (subject to a minimum turn time).
///
/// Parameter defaults are the APRSdroid values, which are widely deployed and
/// well-validated. See ADR-021 in docs/DECISIONS.md.
library;

/// Immutable set of SmartBeaconing tuning parameters.
class SmartBeaconingParams {
  const SmartBeaconingParams({
    required this.fastSpeedKmh,
    required this.fastRateS,
    required this.slowSpeedKmh,
    required this.slowRateS,
    required this.minTurnTimeS,
    required this.minTurnAngleDeg,
    required this.turnSlope,
  });

  final double fastSpeedKmh;
  final int fastRateS;
  final double slowSpeedKmh;
  final int slowRateS;
  final int minTurnTimeS;
  final double minTurnAngleDeg;
  final double turnSlope;

  /// APRSdroid defaults (see ADR-021).
  static const defaults = SmartBeaconingParams(
    fastSpeedKmh: 100,
    fastRateS: 180,
    slowSpeedKmh: 5,
    slowRateS: 1800,
    minTurnTimeS: 15,
    minTurnAngleDeg: 28,
    turnSlope: 255,
  );

  SmartBeaconingParams copyWith({
    double? fastSpeedKmh,
    int? fastRateS,
    double? slowSpeedKmh,
    int? slowRateS,
    int? minTurnTimeS,
    double? minTurnAngleDeg,
    double? turnSlope,
  }) => SmartBeaconingParams(
    fastSpeedKmh: fastSpeedKmh ?? this.fastSpeedKmh,
    fastRateS: fastRateS ?? this.fastRateS,
    slowSpeedKmh: slowSpeedKmh ?? this.slowSpeedKmh,
    slowRateS: slowRateS ?? this.slowRateS,
    minTurnTimeS: minTurnTimeS ?? this.minTurnTimeS,
    minTurnAngleDeg: minTurnAngleDeg ?? this.minTurnAngleDeg,
    turnSlope: turnSlope ?? this.turnSlope,
  );

  Map<String, dynamic> toMap() => {
    'fastSpeedKmh': fastSpeedKmh,
    'fastRateS': fastRateS,
    'slowSpeedKmh': slowSpeedKmh,
    'slowRateS': slowRateS,
    'minTurnTimeS': minTurnTimeS,
    'minTurnAngleDeg': minTurnAngleDeg,
    'turnSlope': turnSlope,
  };

  factory SmartBeaconingParams.fromMap(
    Map<String, dynamic> m,
  ) => SmartBeaconingParams(
    fastSpeedKmh:
        (m['fastSpeedKmh'] as num?)?.toDouble() ?? defaults.fastSpeedKmh,
    fastRateS: (m['fastRateS'] as num?)?.toInt() ?? defaults.fastRateS,
    slowSpeedKmh:
        (m['slowSpeedKmh'] as num?)?.toDouble() ?? defaults.slowSpeedKmh,
    slowRateS: (m['slowRateS'] as num?)?.toInt() ?? defaults.slowRateS,
    minTurnTimeS: (m['minTurnTimeS'] as num?)?.toInt() ?? defaults.minTurnTimeS,
    minTurnAngleDeg:
        (m['minTurnAngleDeg'] as num?)?.toDouble() ?? defaults.minTurnAngleDeg,
    turnSlope: (m['turnSlope'] as num?)?.toDouble() ?? defaults.turnSlope,
  );
}

/// Pure-function SmartBeaconing computations.
abstract class SmartBeaconing {
  SmartBeaconing._();

  /// Computes the beacon interval in seconds for the given [speedKmh].
  ///
  /// - speed ≥ [SmartBeaconingParams.fastSpeedKmh] → [SmartBeaconingParams.fastRateS]
  /// - speed ≤ [SmartBeaconingParams.slowSpeedKmh] → [SmartBeaconingParams.slowRateS]
  /// - between → inverse-proportional (original HamHUD SmartBeaconing™ formula)
  ///
  /// Formula: `interval = fastRate × fastSpeed / speed`
  ///
  /// This keeps beacon density (beacons per km) roughly constant across speeds,
  /// unlike linear interpolation which under-beacons at moderate speeds. It
  /// matches the canonical implementation used by Dire Wolf and hardware TNCs.
  static int computeInterval(SmartBeaconingParams p, double speedKmh) {
    if (speedKmh >= p.fastSpeedKmh) return p.fastRateS;
    if (speedKmh <= p.slowSpeedKmh) return p.slowRateS;

    return (p.fastRateS * p.fastSpeedKmh / speedKmh).round().clamp(
      p.fastRateS,
      p.slowRateS,
    );
  }

  /// Computes the turn threshold in degrees for the given [speedKmh].
  ///
  /// Formula: `(turnSlope / speedMph) + minTurnAngleDeg`
  /// Capped at 180° for safety when speed is near zero.
  ///
  /// [SmartBeaconingParams.turnSlope] has units of **degrees·mph** per the
  /// original SmartBeaconing™ specification. Speed must be converted to mph
  /// before dividing; using km/h produces a threshold that is ~60% too small
  /// at typical driving speeds.
  static double turnThreshold(SmartBeaconingParams p, double speedKmh) {
    if (speedKmh <= 0) return 180.0;
    final speedMph = speedKmh / 1.609344;
    return (p.turnSlope / speedMph + p.minTurnAngleDeg).clamp(0.0, 180.0);
  }

  /// Returns true when a turn-triggered beacon should fire.
  ///
  /// Conditions:
  /// 1. [headingChangeDeg] exceeds the computed turn threshold for [speedKmh].
  /// 2. [timeSinceLastBeacon] ≥ [SmartBeaconingParams.minTurnTimeS].
  static bool shouldTriggerTurn(
    SmartBeaconingParams p,
    double speedKmh,
    double headingChangeDeg,
    Duration timeSinceLastBeacon,
  ) {
    if (timeSinceLastBeacon.inSeconds < p.minTurnTimeS) return false;
    return headingChangeDeg.abs() >= turnThreshold(p, speedKmh);
  }
}
