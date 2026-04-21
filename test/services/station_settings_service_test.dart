import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_aprs/core/connection/aprs_is_filter_config.dart';
import 'package:meridian_aprs/services/station_settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_secure_credential_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<StationSettingsService> buildService() async {
    final prefs = await SharedPreferences.getInstance();
    return StationSettingsService(prefs, store: FakeSecureCredentialStore());
  }

  group('APRS-IS filter persistence', () {
    test('defaults to Regional on first launch', () async {
      final service = await buildService();
      expect(service.aprsIsFilter, AprsIsFilterConfig.defaultConfig);
      expect(service.aprsIsFilter.preset, AprsIsFilterPreset.regional);
    });

    test('setAprsIsFilter notifies listeners', () async {
      final service = await buildService();
      int notifications = 0;
      service.addListener(() => notifications++);

      await service.setAprsIsFilter(AprsIsFilterConfig.local);
      expect(notifications, 1);
      expect(service.aprsIsFilter, AprsIsFilterConfig.local);
    });

    test('setAprsIsFilter is a no-op when value is unchanged', () async {
      final service = await buildService();
      await service.setAprsIsFilter(AprsIsFilterConfig.regional);
      int notifications = 0;
      service.addListener(() => notifications++);

      // Same config again — should not fire.
      await service.setAprsIsFilter(AprsIsFilterConfig.regional);
      expect(notifications, 0);
    });

    test(
      'round-trip through SharedPreferences preserves preset and tuple',
      () async {
        final first = await buildService();
        const custom = AprsIsFilterConfig(
          preset: AprsIsFilterPreset.custom,
          padPct: 0.35,
          minRadiusKm: 75,
        );
        await first.setAprsIsFilter(custom);

        // New service instance reading the same prefs.
        final second = await buildService();
        expect(second.aprsIsFilter, custom);
      },
    );

    test(
      'Custom tuple is remembered independently of named preset switching',
      () async {
        final service = await buildService();

        // User sets a Custom tuple.
        const customTuple = AprsIsFilterConfig(
          preset: AprsIsFilterPreset.custom,
          padPct: 0.35,
          minRadiusKm: 75,
        );
        await service.setAprsIsFilter(customTuple);

        // User switches to Regional preset (snaps to Regional values).
        await service.setAprsIsFilter(AprsIsFilterConfig.regional);
        expect(service.aprsIsFilter, AprsIsFilterConfig.regional);

        // User switches back to Custom — but the spec requires the UI layer
        // to restore the last Custom values. This service-level test confirms
        // the prefs-based mechanism supports that: switching back to Custom
        // with explicit values is a simple setAprsIsFilter call.
        await service.setAprsIsFilter(customTuple);
        expect(service.aprsIsFilter, customTuple);
      },
    );

    test(
      'remembered Custom tuple survives a round-trip through a named preset',
      () async {
        final service = await buildService();

        // Initially no remembered Custom.
        expect(service.aprsIsFilterCustom, isNull);

        // User tweaks an advanced slider — caller (UI) writes both the
        // active filter and the remembered Custom slot.
        const tupleA = AprsIsFilterConfig(
          preset: AprsIsFilterPreset.custom,
          padPct: 0.35,
          minRadiusKm: 75,
        );
        await service.setAprsIsFilter(tupleA);
        await service.setAprsIsFilterCustom(tupleA);
        expect(service.aprsIsFilterCustom, tupleA);

        // Hop through a named preset. This must NOT clobber the remembered
        // Custom tuple.
        await service.setAprsIsFilter(AprsIsFilterConfig.regional);
        expect(service.aprsIsFilter, AprsIsFilterConfig.regional);
        expect(service.aprsIsFilterCustom, tupleA);

        // The UI's "restore last Custom" path reads aprsIsFilterCustom and
        // writes it back as the active filter.
        final restored = service.aprsIsFilterCustom!;
        await service.setAprsIsFilter(restored);
        expect(service.aprsIsFilter, tupleA);
      },
    );

    test(
      'aprsIsFilterCustom is null when either custom key is absent',
      () async {
        // Only one of the two keys set — the getter should still return null
        // because a partial record is not a valid tuple.
        SharedPreferences.setMockInitialValues({
          'aprs_is_filter_custom_pad_pct': 0.35,
          // min radius key deliberately absent
        });
        final service = await buildService();
        expect(service.aprsIsFilterCustom, isNull);
      },
    );

    test('unknown preset name in prefs falls back to Regional', () async {
      SharedPreferences.setMockInitialValues({
        'aprs_is_filter_preset': 'bogus-preset',
        'aprs_is_filter_pad_pct': 0.25,
        'aprs_is_filter_min_radius_km': 50.0,
      });

      final service = await buildService();
      expect(service.aprsIsFilter.preset, AprsIsFilterPreset.regional);
    });
  });
}
