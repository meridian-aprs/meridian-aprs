/// Widget regression guard for [BeaconFAB] — pins the tap dispatch in each
/// [BeaconMode], the long-press cooldown, and the "Xm ago" subtitle (issue #86).
///
/// Auto/smart taps must call [BeaconingService.startBeaconing] /
/// [BeaconingService.stopBeaconing], **not** [BeaconingService.beaconNow] —
/// regressing that behavior turns the timed/SmartBeaconing loop into a
/// one-shot transmit. The dispatch lives in [beaconFabCallbacksFor], adopted
/// by [MobileScaffold]; this test exercises the same helper to keep the
/// guard load-bearing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meridian_aprs/core/connection/connection_registry.dart';
import 'package:meridian_aprs/services/beaconing_service.dart';
import 'package:meridian_aprs/services/station_settings_service.dart';
import 'package:meridian_aprs/services/tx_service.dart';
import 'package:meridian_aprs/ui/widgets/beacon_fab.dart';

import '../helpers/fake_secure_credential_store.dart';

// ---------------------------------------------------------------------------
// Recording fake — captures invocations of the three methods the FAB might
// call, and lets each test fix `mode` / `isActive` independently of timers,
// GPS, or persisted prefs. Mirrors the `_RecordingTxService` shape in
// `test/services/beaconing_service_test.dart`.
// ---------------------------------------------------------------------------

class _RecordingBeaconingService extends BeaconingService {
  _RecordingBeaconingService(
    super.settings,
    super.tx, {
    BeaconMode mode = BeaconMode.manual,
    bool isActive = false,
  }) : _testMode = mode,
       _testIsActive = isActive;

  final BeaconMode _testMode;
  bool _testIsActive;

  int beaconNowCalls = 0;
  int startCalls = 0;
  int stopCalls = 0;

  @override
  BeaconMode get mode => _testMode;

  @override
  bool get isActive => _testIsActive;

  @override
  Future<void> beaconNow() async {
    beaconNowCalls++;
  }

  @override
  Future<void> startBeaconing() async {
    startCalls++;
    _testIsActive = true;
  }

  @override
  Future<void> stopBeaconing() async {
    stopCalls++;
    _testIsActive = false;
  }
}

Future<_RecordingBeaconingService> _makeService({
  required BeaconMode mode,
  required bool isActive,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final settings = StationSettingsService(
    prefs,
    store: FakeSecureCredentialStore(),
  );
  final registry = ConnectionRegistry();
  final tx = TxService(registry, settings);
  return _RecordingBeaconingService(
    settings,
    tx,
    mode: mode,
    isActive: isActive,
  );
}

Future<void> _pumpFab(
  WidgetTester tester, {
  required _RecordingBeaconingService service,
  DateTime? lastBeaconAt,
}) async {
  final callbacks = beaconFabCallbacksFor(service);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: BeaconFAB(
            isBeaconing: service.isActive,
            mode: service.mode,
            lastBeaconAt: lastBeaconAt,
            onTap: callbacks.onTap,
            onLongPress: callbacks.onLongPress,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('BeaconFAB tap dispatch — issue #86', () {
    testWidgets('manual mode tap → beaconNow', (tester) async {
      final svc = await _makeService(mode: BeaconMode.manual, isActive: false);
      await _pumpFab(tester, service: svc);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(svc.beaconNowCalls, 1);
      expect(svc.startCalls, 0);
      expect(svc.stopCalls, 0);
    });

    testWidgets('auto mode + idle tap → startBeaconing (NOT beaconNow)', (
      tester,
    ) async {
      final svc = await _makeService(mode: BeaconMode.auto, isActive: false);
      await _pumpFab(tester, service: svc);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(svc.startCalls, 1);
      expect(svc.beaconNowCalls, 0, reason: 'regression #86 — must not fire');
      expect(svc.stopCalls, 0);
    });

    testWidgets('auto mode + active tap → stopBeaconing (NOT beaconNow)', (
      tester,
    ) async {
      final svc = await _makeService(mode: BeaconMode.auto, isActive: true);
      await _pumpFab(tester, service: svc);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(svc.stopCalls, 1);
      expect(svc.beaconNowCalls, 0, reason: 'regression #86 — must not fire');
      expect(svc.startCalls, 0);
    });

    testWidgets('smart mode + idle tap → startBeaconing (NOT beaconNow)', (
      tester,
    ) async {
      final svc = await _makeService(mode: BeaconMode.smart, isActive: false);
      await _pumpFab(tester, service: svc);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(svc.startCalls, 1);
      expect(svc.beaconNowCalls, 0, reason: 'regression #86 — must not fire');
      expect(svc.stopCalls, 0);
    });

    testWidgets('smart mode + active tap → stopBeaconing (NOT beaconNow)', (
      tester,
    ) async {
      final svc = await _makeService(mode: BeaconMode.smart, isActive: true);
      await _pumpFab(tester, service: svc);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(svc.stopCalls, 1);
      expect(svc.beaconNowCalls, 0, reason: 'regression #86 — must not fire');
      expect(svc.startCalls, 0);
    });
  });

  group('BeaconFAB long-press cooldown', () {
    testWidgets(
      'manual mode: second long-press inside 30s window is suppressed',
      (tester) async {
        final svc = await _makeService(
          mode: BeaconMode.manual,
          isActive: false,
        );
        await _pumpFab(tester, service: svc);

        await tester.longPress(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();

        expect(svc.beaconNowCalls, 1);

        await tester.longPress(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();

        expect(
          svc.beaconNowCalls,
          1,
          reason: 'second long-press within 30s must be suppressed',
        );
        expect(
          find.text('Please wait 30 seconds between manual beacons.'),
          findsOneWidget,
        );
      },
    );
  });

  group('BeaconFAB "Xm ago" subtitle', () {
    testWidgets('renders "5m ago" for a 5-minute-old lastBeaconAt', (
      tester,
    ) async {
      final svc = await _makeService(mode: BeaconMode.manual, isActive: false);
      // BeaconFAB's _agoText uses DateTime.now() directly (beacon_fab.dart:109);
      // bucket thresholds are coarse (60s / 60m), so a 5-minute delta is
      // deterministic regardless of millisecond drift in the test runner.
      final five = DateTime.now().subtract(const Duration(minutes: 5));
      await _pumpFab(tester, service: svc, lastBeaconAt: five);

      expect(find.text('5m ago'), findsOneWidget);
    });
  });
}
