import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_aprs/core/connection/aprs_is_filter_config.dart';

void main() {
  group('AprsIsFilterConfig', () {
    test('Local preset values match spec', () {
      expect(AprsIsFilterConfig.local.preset, AprsIsFilterPreset.local);
      expect(AprsIsFilterConfig.local.padPct, 0.10);
      expect(AprsIsFilterConfig.local.minRadiusKm, 25);
    });

    test('Regional preset values match spec', () {
      expect(AprsIsFilterConfig.regional.preset, AprsIsFilterPreset.regional);
      expect(AprsIsFilterConfig.regional.padPct, 0.25);
      expect(AprsIsFilterConfig.regional.minRadiusKm, 50);
    });

    test('Wide preset values match spec', () {
      expect(AprsIsFilterConfig.wide.preset, AprsIsFilterPreset.wide);
      expect(AprsIsFilterConfig.wide.padPct, 0.50);
      expect(AprsIsFilterConfig.wide.minRadiusKm, 150);
    });

    test('defaultConfig equals Regional (v0.12 parity)', () {
      expect(AprsIsFilterConfig.defaultConfig, AprsIsFilterConfig.regional);
    });

    group('fromPreset', () {
      test('resolves named presets to their config', () {
        expect(
          AprsIsFilterConfig.fromPreset(AprsIsFilterPreset.local),
          AprsIsFilterConfig.local,
        );
        expect(
          AprsIsFilterConfig.fromPreset(AprsIsFilterPreset.regional),
          AprsIsFilterConfig.regional,
        );
        expect(
          AprsIsFilterConfig.fromPreset(AprsIsFilterPreset.wide),
          AprsIsFilterConfig.wide,
        );
      });

      test('returns null for Custom (no canonical tuple)', () {
        expect(
          AprsIsFilterConfig.fromPreset(AprsIsFilterPreset.custom),
          isNull,
        );
      });
    });

    group('copyWith', () {
      test('returns identical config when no overrides given', () {
        final c = AprsIsFilterConfig.regional;
        expect(c.copyWith(), c);
      });

      test('overrides individual fields', () {
        final c = AprsIsFilterConfig.regional.copyWith(
          preset: AprsIsFilterPreset.custom,
          padPct: 0.35,
        );
        expect(c.preset, AprsIsFilterPreset.custom);
        expect(c.padPct, 0.35);
        // Unchanged field preserved.
        expect(c.minRadiusKm, AprsIsFilterConfig.regional.minRadiusKm);
      });
    });

    test('equality compares all fields', () {
      expect(
        AprsIsFilterConfig.regional,
        const AprsIsFilterConfig(
          preset: AprsIsFilterPreset.regional,
          padPct: 0.25,
          minRadiusKm: 50,
        ),
      );
      // Differ in preset only.
      expect(
        AprsIsFilterConfig.regional ==
            AprsIsFilterConfig.regional.copyWith(
              preset: AprsIsFilterPreset.custom,
            ),
        isFalse,
      );
    });

    test('hashCode is consistent with equality', () {
      expect(
        AprsIsFilterConfig.regional.hashCode,
        const AprsIsFilterConfig(
          preset: AprsIsFilterPreset.regional,
          padPct: 0.25,
          minRadiusKm: 50,
        ).hashCode,
      );
    });
  });
}
