/// Widget tests for the receive-only / licensed UI gating added alongside
/// the new Settings → My Station "Licensed amateur radio operator" switch.
///
/// Pins the contract that flipping `isLicensed` off in [StationSettingsService]
/// hides every TX-only piece of UI in real time:
///
///   * [SettingsScreen] — the **Beaconing** category is removed from the list.
///   * [MyStationSettingsContent] — Callsign / SSID / address / symbol /
///     comment / position-source fields are removed; a receive-only
///     explainer takes their place.
///
/// Toggling Licensed back on restores the full layout in the same session.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meridian_aprs/core/connection/connection_registry.dart';
import 'package:meridian_aprs/screens/settings/advanced_mode_controller.dart';
import 'package:meridian_aprs/screens/settings/category/my_station_screen.dart';
import 'package:meridian_aprs/screens/settings_screen.dart';
import 'package:meridian_aprs/services/beaconing_service.dart';
import 'package:meridian_aprs/services/station_settings_service.dart';
import 'package:meridian_aprs/services/tx_service.dart';

import '../../helpers/fake_geolocator_adapter.dart';
import '../../helpers/fake_secure_credential_store.dart';

// ---------------------------------------------------------------------------
// Harness — only wires the providers MyStation + the SettingsScreen list pane
// actually read. Other settings categories (Beaconing, Notifications, etc.)
// are constructed inside `_visibleCategories` but their Provider lookups only
// fire when the category is actually entered, so they don't need to be in the
// tree for these tests.
// ---------------------------------------------------------------------------

class _Harness {
  _Harness._({
    required this.settings,
    required this.beaconing,
    required this.widget,
  });

  final StationSettingsService settings;
  final BeaconingService beaconing;
  final Widget widget;

  static Future<_Harness> create({
    required bool isLicensed,
    required Widget child,
  }) async {
    SharedPreferences.setMockInitialValues({
      'user_callsign': 'W1ABC',
      'user_ssid': 7,
      'user_is_licensed': isLicensed,
    });
    final prefs = await SharedPreferences.getInstance();
    final settings = StationSettingsService(
      prefs,
      store: FakeSecureCredentialStore(),
    );
    final registry = ConnectionRegistry();
    final tx = TxService(registry, settings);
    final beaconing = BeaconingService(
      settings,
      tx,
      geo: FakeGeolocatorAdapter(),
    );
    final advanced = await AdvancedModeController.create();

    final widget = MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<StationSettingsService>.value(value: settings),
          ChangeNotifierProvider<BeaconingService>.value(value: beaconing),
          ChangeNotifierProvider<AdvancedModeController>.value(value: advanced),
        ],
        child: child,
      ),
    );

    return _Harness._(settings: settings, beaconing: beaconing, widget: widget);
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MyStationSettingsContent — license gating', () {
    testWidgets('licensed: identity + beacon fields are visible', (
      tester,
    ) async {
      final h = await _Harness.create(
        isLicensed: true,
        child: const Scaffold(body: MyStationSettingsContent()),
      );
      await tester.pumpWidget(h.widget);
      await tester.pumpAndSettle();

      // Licensed switch is always present and is on.
      expect(find.text('Licensed amateur radio operator'), findsOneWidget);
      final switchTile = tester.widget<SwitchListTile>(
        find.byType(SwitchListTile),
      );
      expect(switchTile.value, isTrue);

      // Identity fields are visible.
      expect(find.text('Callsign'), findsOneWidget);
      expect(find.text('SSID'), findsOneWidget);
      expect(find.text('Your address'), findsOneWidget);

      // Position-source section header is visible.
      expect(find.text('POSITION SOURCE'), findsOneWidget);

      // The receive-only explainer must NOT be present.
      expect(find.textContaining('Receive-only mode is on'), findsNothing);
    });

    testWidgets('unlicensed: identity + beacon fields are hidden', (
      tester,
    ) async {
      final h = await _Harness.create(
        isLicensed: false,
        child: const Scaffold(body: MyStationSettingsContent()),
      );
      await tester.pumpWidget(h.widget);
      await tester.pumpAndSettle();

      // Switch is present and off.
      final switchTile = tester.widget<SwitchListTile>(
        find.byType(SwitchListTile),
      );
      expect(switchTile.value, isFalse);

      // Identity / beacon fields are gone.
      expect(find.text('Callsign'), findsNothing);
      expect(find.text('SSID'), findsNothing);
      expect(find.text('Your address'), findsNothing);
      expect(find.text('POSITION SOURCE'), findsNothing);

      // The receive-only explainer is shown so the screen isn't barren.
      expect(find.textContaining('Receive-only mode is on'), findsOneWidget);
    });

    testWidgets('toggling Licensed re-renders the field set live', (
      tester,
    ) async {
      final h = await _Harness.create(
        isLicensed: false,
        child: const Scaffold(body: MyStationSettingsContent()),
      );
      await tester.pumpWidget(h.widget);
      await tester.pumpAndSettle();

      expect(find.text('Callsign'), findsNothing);

      await h.settings.setIsLicensed(true);
      await tester.pumpAndSettle();

      expect(find.text('Callsign'), findsOneWidget);
      expect(find.textContaining('Receive-only mode is on'), findsNothing);

      await h.settings.setIsLicensed(false);
      await tester.pumpAndSettle();

      expect(find.text('Callsign'), findsNothing);
      expect(find.textContaining('Receive-only mode is on'), findsOneWidget);
    });
  });

  group('SettingsScreen — license gating', () {
    // Force a wide test surface so the master/detail desktop layout renders
    // and the category list is fully visible without scrolling.
    Future<void> setWide(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('licensed: Beaconing category is in the list', (tester) async {
      await setWide(tester);
      final h = await _Harness.create(
        isLicensed: true,
        child: const SettingsScreen(),
      );
      await tester.pumpWidget(h.widget);
      await tester.pumpAndSettle();

      expect(find.text('Beaconing'), findsOneWidget);
      expect(find.text('My Station'), findsAtLeastNWidgets(1));
    });

    testWidgets('unlicensed: Beaconing category is hidden', (tester) async {
      await setWide(tester);
      final h = await _Harness.create(
        isLicensed: false,
        child: const SettingsScreen(),
      );
      await tester.pumpWidget(h.widget);
      await tester.pumpAndSettle();

      expect(find.text('Beaconing'), findsNothing);
      // Other categories still present — gating is targeted, not blanket.
      expect(find.text('My Station'), findsAtLeastNWidgets(1));
      expect(find.text('Connections'), findsOneWidget);
      expect(find.text('Messaging'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);
    });

    testWidgets('toggling Licensed adds/removes Beaconing from the list', (
      tester,
    ) async {
      await setWide(tester);
      final h = await _Harness.create(
        isLicensed: false,
        child: const SettingsScreen(),
      );
      await tester.pumpWidget(h.widget);
      await tester.pumpAndSettle();

      expect(find.text('Beaconing'), findsNothing);

      await h.settings.setIsLicensed(true);
      await tester.pumpAndSettle();

      expect(find.text('Beaconing'), findsOneWidget);

      await h.settings.setIsLicensed(false);
      await tester.pumpAndSettle();

      expect(find.text('Beaconing'), findsNothing);
    });

    testWidgets('selection survives reorder when a category appears above it', (
      tester,
    ) async {
      // Pin the desktop-master/detail invariant: when we tap a category and
      // then a *different* category becomes visible above it (Beaconing
      // appears between My Station and the user's selection), the selection
      // must continue pointing at the same category — not silently shift to
      // whatever lands at the old index.
      //
      // Uses About as the selected category because its content widget has
      // zero provider dependencies, keeping this test focused on the
      // selection state machine rather than provider plumbing.
      await setWide(tester);
      final h = await _Harness.create(
        isLicensed: false,
        child: const SettingsScreen(),
      );
      await tester.pumpWidget(h.widget);
      await tester.pumpAndSettle();

      await tester.tap(find.text('About'));
      await tester.pumpAndSettle();

      // Two matches: the list entry + the detail header above the divider.
      expect(find.text('About'), findsNWidgets(2));

      // Flip Licensed on — Beaconing inserts at index 1; About slides one
      // slot deeper. Selection must remain on About.
      await h.settings.setIsLicensed(true);
      await tester.pumpAndSettle();

      expect(
        find.text('About'),
        findsNWidgets(2),
        reason:
            'selection follows the category across reorders — the detail '
            'header should still show About, not the category that happens '
            'to land at the old index',
      );
    });

    testWidgets(
      'selection falls back to My Station when its category disappears',
      (tester) async {
        await setWide(tester);
        final h = await _Harness.create(
          isLicensed: true,
          child: const SettingsScreen(),
        );
        await tester.pumpWidget(h.widget);
        await tester.pumpAndSettle();

        // Select Beaconing.
        await tester.tap(find.text('Beaconing'));
        await tester.pumpAndSettle();

        // Disable Licensed — Beaconing disappears from the visible list.
        await h.settings.setIsLicensed(false);
        await tester.pumpAndSettle();

        // The detail pane must now show My Station, not whatever happened to
        // shift into the old index slot.
        final myStationTexts = find.text('My Station');
        expect(
          myStationTexts,
          findsNWidgets(2),
          reason:
              'when the selected category disappears, selection falls back to '
              'the first visible category (My Station) — both the list entry '
              'and the detail header must show it',
        );
        expect(find.text('Beaconing'), findsNothing);
      },
    );
  });
}
