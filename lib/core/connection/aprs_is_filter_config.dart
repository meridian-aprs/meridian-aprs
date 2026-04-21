/// APRS-IS server-side filter configuration.
///
/// Surfaces the viewport-adaptive `#filter a/` line that
/// [AprsIsConnection.updateFilter] writes to the server as a user-configurable
/// pair: viewport pad percentage and minimum radius. Three named presets are
/// provided (`local`, `regional`, `wide`) plus a `custom` bucket that
/// remembers the user's own tuple independently of the preset values.
///
/// The APRS-IS `a/` filter is purely geographic; station visibility / ageing
/// is a separate concern controlled by `StationService.stationMaxAgeMinutes`
/// and the on-map time-window filter.
library;

/// Identifies one of the preset APRS-IS server-side filter shapes, or the
/// `custom` bucket for a user-tweaked tuple.
enum AprsIsFilterPreset { local, regional, wide, custom }

/// Immutable snapshot of the APRS-IS server-side filter configuration.
class AprsIsFilterConfig {
  const AprsIsFilterConfig({
    required this.preset,
    required this.padPct,
    required this.minRadiusKm,
  });

  /// The preset the user last selected explicitly. [AprsIsFilterPreset.custom]
  /// means the user has tweaked an advanced value away from a named preset;
  /// the raw tuple is what matters for filter math and the preset is metadata
  /// for UI display only.
  final AprsIsFilterPreset preset;

  /// Fraction by which the viewport bounding box is padded on each edge
  /// before being sent to APRS-IS. `0.25` means 25% extra on every side.
  final double padPct;

  /// Minimum half-extent radius, in kilometres. Enforced after padding so
  /// very close zooms still receive a useful feed. Always stored in km; the
  /// UI converts to miles for display when the user's distance preference is
  /// imperial.
  final double minRadiusKm;

  // ---------------------------------------------------------------------------
  // Preset factories
  // ---------------------------------------------------------------------------

  /// Tight local view: 10% pad, 25 km minimum.
  static const local = AprsIsFilterConfig(
    preset: AprsIsFilterPreset.local,
    padPct: 0.10,
    minRadiusKm: 25,
  );

  /// v0.12 default: 25% pad, 50 km minimum.
  static const regional = AprsIsFilterConfig(
    preset: AprsIsFilterPreset.regional,
    padPct: 0.25,
    minRadiusKm: 50,
  );

  /// Wide-area view: 50% pad, 150 km minimum.
  static const wide = AprsIsFilterConfig(
    preset: AprsIsFilterPreset.wide,
    padPct: 0.50,
    minRadiusKm: 150,
  );

  /// Application default — equivalent to the v0.12 hardcoded behaviour.
  static const defaultConfig = regional;

  /// Resolve the value tuple for a named preset. Returns null for
  /// [AprsIsFilterPreset.custom] because custom has no canonical tuple.
  static AprsIsFilterConfig? fromPreset(AprsIsFilterPreset preset) =>
      switch (preset) {
        AprsIsFilterPreset.local => local,
        AprsIsFilterPreset.regional => regional,
        AprsIsFilterPreset.wide => wide,
        AprsIsFilterPreset.custom => null,
      };

  AprsIsFilterConfig copyWith({
    AprsIsFilterPreset? preset,
    double? padPct,
    double? minRadiusKm,
  }) => AprsIsFilterConfig(
    preset: preset ?? this.preset,
    padPct: padPct ?? this.padPct,
    minRadiusKm: minRadiusKm ?? this.minRadiusKm,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AprsIsFilterConfig &&
          other.preset == preset &&
          other.padPct == padPct &&
          other.minRadiusKm == minRadiusKm;

  @override
  int get hashCode => Object.hash(preset, padPct, minRadiusKm);

  @override
  String toString() =>
      'AprsIsFilterConfig(preset: $preset, padPct: $padPct, '
      'minRadiusKm: $minRadiusKm)';
}
