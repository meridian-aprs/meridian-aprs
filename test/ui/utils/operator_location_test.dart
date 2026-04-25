import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:meridian_aprs/core/connection/connection_registry.dart';
import 'package:meridian_aprs/services/beaconing_service.dart';
import 'package:meridian_aprs/services/station_settings_service.dart';
import 'package:meridian_aprs/services/tx_service.dart';
import 'package:meridian_aprs/ui/utils/operator_location.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_secure_credential_store.dart';

/// Subclass that lets a test pin `lastKnownLocation` to a known value.
class _StubBeaconingService extends BeaconingService {
  _StubBeaconingService(super.settings, super.tx);

  LatLng? stubLocation;

  @override
  LatLng? get lastKnownLocation => stubLocation;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<({StationSettingsService settings, _StubBeaconingService beacon})>
  build() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = StationSettingsService(
      prefs,
      store: FakeSecureCredentialStore(),
    );
    final tx = TxService(ConnectionRegistry(), settings);
    final beacon = _StubBeaconingService(settings, tx);
    return (settings: settings, beacon: beacon);
  }

  /// Pumps a widget that captures the resolved operator location.
  Future<LatLng?> resolve(
    WidgetTester tester, {
    required StationSettingsService settings,
    required BeaconingService beacon,
  }) async {
    LatLng? captured;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StationSettingsService>.value(value: settings),
          ChangeNotifierProvider<BeaconingService>.value(value: beacon),
        ],
        child: Builder(
          builder: (context) {
            captured = resolveOperatorLocation(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return captured;
  }

  group('resolveOperatorLocation', () {
    testWidgets('returns manual coords when manual selected and set', (
      tester,
    ) async {
      final ctx = await build();
      await ctx.settings.setLocationSource(LocationSource.manual);
      await ctx.settings.setManualPosition(40.0, -75.0);

      final result = await resolve(
        tester,
        settings: ctx.settings,
        beacon: ctx.beacon,
      );

      expect(result, equals(LatLng(40.0, -75.0)));
    });

    testWidgets(
      'falls back to GPS when manual selected but no manual position',
      (tester) async {
        final ctx = await build();
        await ctx.settings.setLocationSource(LocationSource.manual);
        // Note: no manual position stored.
        ctx.beacon.stubLocation = LatLng(35.0, -120.0);

        final result = await resolve(
          tester,
          settings: ctx.settings,
          beacon: ctx.beacon,
        );

        expect(result, equals(LatLng(35.0, -120.0)));
      },
    );

    testWidgets('returns GPS fix when GPS source selected', (tester) async {
      final ctx = await build();
      await ctx.settings.setLocationSource(LocationSource.gps);
      ctx.beacon.stubLocation = LatLng(51.5, -0.1);

      final result = await resolve(
        tester,
        settings: ctx.settings,
        beacon: ctx.beacon,
      );

      expect(result, equals(LatLng(51.5, -0.1)));
    });

    testWidgets('prefers manual over GPS when both are available', (
      tester,
    ) async {
      final ctx = await build();
      await ctx.settings.setLocationSource(LocationSource.manual);
      await ctx.settings.setManualPosition(40.0, -75.0);
      ctx.beacon.stubLocation = LatLng(51.5, -0.1);

      final result = await resolve(
        tester,
        settings: ctx.settings,
        beacon: ctx.beacon,
      );

      expect(result, equals(LatLng(40.0, -75.0)));
    });

    testWidgets('returns null when GPS source and no fix yet', (tester) async {
      final ctx = await build();
      await ctx.settings.setLocationSource(LocationSource.gps);
      // No GPS fix.
      final result = await resolve(
        tester,
        settings: ctx.settings,
        beacon: ctx.beacon,
      );

      expect(result, isNull);
    });

    testWidgets(
      'returns null when manual selected, no manual coords, no GPS fix',
      (tester) async {
        final ctx = await build();
        await ctx.settings.setLocationSource(LocationSource.manual);
        // No manual, no GPS.
        final result = await resolve(
          tester,
          settings: ctx.settings,
          beacon: ctx.beacon,
        );

        expect(result, isNull);
      },
    );
  });
}
