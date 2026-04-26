import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meridian_aprs/core/connection/connection_registry.dart';
import 'package:meridian_aprs/services/background_service_manager.dart';
import 'package:meridian_aprs/services/beaconing_service.dart';
import 'package:meridian_aprs/services/station_settings_service.dart';
import 'package:meridian_aprs/services/tx_service.dart';

import '../helpers/fake_meridian_connection.dart';
import '../helpers/fake_secure_credential_store.dart';

// ---------------------------------------------------------------------------
// FakeForegroundServiceApi
// ---------------------------------------------------------------------------

class FakeForegroundServiceApi implements ForegroundServiceApi {
  int startCallCount = 0;
  int updateCallCount = 0;
  int stopCallCount = 0;
  int isRunningCallCount = 0;

  String? lastTitle;
  String? lastBody;

  bool startReturnsSuccess;

  /// What `isRunningService()` should return — toggled in tests to simulate
  /// Android killing the FGS without notifying the main isolate.
  bool runningOverride = true;

  FakeForegroundServiceApi({this.startReturnsSuccess = true});

  @override
  Future<ServiceRequestResult> startService({
    required int serviceId,
    required String notificationTitle,
    required String notificationText,
    required void Function() callback,
  }) async {
    startCallCount++;
    lastTitle = notificationTitle;
    lastBody = notificationText;
    return startReturnsSuccess
        ? ServiceRequestSuccess()
        : ServiceRequestFailure(error: Exception('fake failure'));
  }

  @override
  Future<ServiceRequestResult> updateService({
    String? notificationTitle,
    String? notificationText,
  }) async {
    updateCallCount++;
    if (notificationTitle != null) lastTitle = notificationTitle;
    if (notificationText != null) lastBody = notificationText;
    return ServiceRequestSuccess();
  }

  @override
  Future<ServiceRequestResult> stopService() async {
    stopCallCount++;
    return ServiceRequestSuccess();
  }

  @override
  Future<bool> isRunningService() async {
    isRunningCallCount++;
    return runningOverride;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<
  ({
    ConnectionRegistry registry,
    FakeMeridianConnection aprsIs,
    BeaconingService beaconing,
    TxService tx,
  })
>
_buildDeps() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final registry = ConnectionRegistry();
  final aprsIs = FakeMeridianConnection(
    id: 'aprs_is',
    displayName: 'APRS-IS',
    type: ConnectionType.aprsIs,
  );
  registry.register(aprsIs);
  final settings = StationSettingsService(
    prefs,
    store: FakeSecureCredentialStore(),
  );
  final tx = TxService(registry, settings);
  final beaconing = BeaconingService(settings, tx);
  return (registry: registry, aprsIs: aprsIs, beaconing: beaconing, tx: tx);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('BackgroundServiceManager — state', () {
    test('starts in stopped state', () async {
      final deps = await _buildDeps();
      final manager = BackgroundServiceManager(
        registry: deps.registry,
        beaconing: deps.beaconing,
        tx: deps.tx,
        taskApi: FakeForegroundServiceApi(),
      );
      expect(manager.state, BackgroundServiceState.stopped);
      manager.dispose();
    });

    test('isRunning is false when stopped', () async {
      final deps = await _buildDeps();
      final manager = BackgroundServiceManager(
        registry: deps.registry,
        beaconing: deps.beaconing,
        tx: deps.tx,
        taskApi: FakeForegroundServiceApi(),
      );
      expect(manager.isRunning, isFalse);
      manager.dispose();
    });

    test('isRunning is true when running', () async {
      final deps = await _buildDeps();
      final manager = BackgroundServiceManager(
        registry: deps.registry,
        beaconing: deps.beaconing,
        tx: deps.tx,
        taskApi: FakeForegroundServiceApi(),
      );
      manager.setStateForTest(BackgroundServiceState.running);
      expect(manager.isRunning, isTrue);
      manager.dispose();
    });

    test('isRunning is true when reconnecting', () async {
      final deps = await _buildDeps();
      final manager = BackgroundServiceManager(
        registry: deps.registry,
        beaconing: deps.beaconing,
        tx: deps.tx,
        taskApi: FakeForegroundServiceApi(),
      );
      manager.setStateForTest(BackgroundServiceState.reconnecting);
      expect(manager.isRunning, isTrue);
      manager.dispose();
    });

    test('setStateForTest notifies listeners', () async {
      final deps = await _buildDeps();
      final manager = BackgroundServiceManager(
        registry: deps.registry,
        beaconing: deps.beaconing,
        tx: deps.tx,
        taskApi: FakeForegroundServiceApi(),
      );
      var notified = false;
      manager.addListener(() => notified = true);

      manager.setStateForTest(BackgroundServiceState.running);

      expect(notified, isTrue);
      manager.dispose();
    });

    test(
      'reconnecting state is set when a connection reports reconnecting while running',
      () async {
        final deps = await _buildDeps();
        final fake = FakeForegroundServiceApi();
        final manager = BackgroundServiceManager(
          registry: deps.registry,
          beaconing: deps.beaconing,
          tx: deps.tx,
          taskApi: fake,
        );
        manager.setStateForTest(BackgroundServiceState.running);

        // All connections are disconnected → state stays running
        expect(manager.state, BackgroundServiceState.running);
        manager.dispose();
      },
    );

    test('dispose removes listeners from registry and beaconing', () async {
      final deps = await _buildDeps();
      final manager = BackgroundServiceManager(
        registry: deps.registry,
        beaconing: deps.beaconing,
        tx: deps.tx,
        taskApi: FakeForegroundServiceApi(),
      );

      manager.dispose();

      // After dispose, notifying the dependent services must not cause
      // the (now-disposed) manager to call notifyListeners and throw.
      expect(() => deps.registry.notifyListeners(), returnsNormally);
      expect(() => deps.beaconing.notifyListeners(), returnsNormally);
    });
  });

  group('BackgroundServiceManager — notification content', () {
    test(
      'title shows APRS-IS connected when only APRS-IS is connected',
      () async {
        final deps = await _buildDeps();
        final manager = BackgroundServiceManager(
          registry: deps.registry,
          beaconing: deps.beaconing,
          tx: deps.tx,
          taskApi: FakeForegroundServiceApi(),
        );
        // Default state: all connections disconnected → fallback title.
        final title = manager.buildTitleForTest();
        expect(title, 'Meridian — Connected');
        manager.dispose();
      },
    );

    test(
      'title shows APRS-IS connected when APRS-IS connection is connected',
      () async {
        final deps = await _buildDeps();
        final manager = BackgroundServiceManager(
          registry: deps.registry,
          beaconing: deps.beaconing,
          tx: deps.tx,
          taskApi: FakeForegroundServiceApi(),
        );
        deps.aprsIs.setStatus(ConnectionStatus.connected);
        final title = manager.buildTitleForTest();
        expect(title, contains('APRS-IS'));
        manager.dispose();
      },
    );

    test('title shows Reconnecting when state is reconnecting', () async {
      final deps = await _buildDeps();
      final manager = BackgroundServiceManager(
        registry: deps.registry,
        beaconing: deps.beaconing,
        tx: deps.tx,
        taskApi: FakeForegroundServiceApi(),
      );
      manager.setStateForTest(BackgroundServiceState.reconnecting);
      expect(manager.buildTitleForTest(), contains('Reconnecting'));
      manager.dispose();
    });

    test('body shows Beaconing off when inactive', () async {
      final deps = await _buildDeps();
      final manager = BackgroundServiceManager(
        registry: deps.registry,
        beaconing: deps.beaconing,
        tx: deps.tx,
        taskApi: FakeForegroundServiceApi(),
      );
      // BeaconingService is inactive by default.
      expect(manager.buildBodyForTest(), 'Beaconing off');
      manager.dispose();
    });

    test(
      'body shows SmartBeaconing active when smart mode is active',
      () async {
        final deps = await _buildDeps();
        final manager = BackgroundServiceManager(
          registry: deps.registry,
          beaconing: deps.beaconing,
          tx: deps.tx,
          taskApi: FakeForegroundServiceApi(),
        );
        await deps.beaconing.setMode(BeaconMode.smart);

        // isActive is false, so body still says "Beaconing off" (not started).
        expect(manager.buildBodyForTest(), 'Beaconing off');

        manager.dispose();
      },
    );

    test('body shows auto interval when auto mode is active', () async {
      final deps = await _buildDeps();
      final manager = BackgroundServiceManager(
        registry: deps.registry,
        beaconing: deps.beaconing,
        tx: deps.tx,
        taskApi: FakeForegroundServiceApi(),
      );
      await deps.beaconing.setMode(BeaconMode.auto);
      await deps.beaconing.setAutoInterval(300);

      // isActive is still false → "Beaconing off".
      expect(manager.buildBodyForTest(), 'Beaconing off');

      manager.dispose();
    });

    test('formatInterval formats seconds correctly', () async {
      final deps = await _buildDeps();
      final manager = BackgroundServiceManager(
        registry: deps.registry,
        beaconing: deps.beaconing,
        tx: deps.tx,
        taskApi: FakeForegroundServiceApi(),
      );
      await deps.beaconing.setMode(BeaconMode.auto);
      await deps.beaconing.setAutoInterval(30);
      expect(manager.buildBodyForTest(), isNotEmpty);
      manager.dispose();
    });
  });

  group('BackgroundServiceManager — IPC packet ingest', () {
    test('beacon_sent IPC with aprs_line invokes onPacketLogged', () async {
      final deps = await _buildDeps();
      final logged = <String>[];
      final manager = BackgroundServiceManager(
        registry: deps.registry,
        beaconing: deps.beaconing,
        tx: deps.tx,
        taskApi: FakeForegroundServiceApi(),
        onPacketLogged: logged.add,
      );

      manager.debugDispatchTaskData({
        'type': 'beacon_sent',
        'ts': 123,
        'aprs_line': 'NOCALL-7>APMDN0:=4012.34N/07412.34W>test',
      });

      expect(logged, ['NOCALL-7>APMDN0:=4012.34N/07412.34W>test']);
      manager.dispose();
    });

    test('bulletin_sent IPC with aprs_line invokes onPacketLogged', () async {
      final deps = await _buildDeps();
      final logged = <String>[];
      final manager = BackgroundServiceManager(
        registry: deps.registry,
        beaconing: deps.beaconing,
        tx: deps.tx,
        taskApi: FakeForegroundServiceApi(),
        onPacketLogged: logged.add,
      );

      manager.debugDispatchTaskData({
        'type': 'bulletin_sent',
        'aprs_line': 'NOCALL-7>APMDN0::BLN0     :Net at 8pm',
      });

      expect(logged, ['NOCALL-7>APMDN0::BLN0     :Net at 8pm']);
      manager.dispose();
    });

    test(
      'beacon_sent IPC without aprs_line is a no-op (legacy payload safety)',
      () async {
        final deps = await _buildDeps();
        final logged = <String>[];
        final manager = BackgroundServiceManager(
          registry: deps.registry,
          beaconing: deps.beaconing,
          tx: deps.tx,
          taskApi: FakeForegroundServiceApi(),
          onPacketLogged: logged.add,
        );

        manager.debugDispatchTaskData({'type': 'beacon_sent', 'ts': 123});

        expect(logged, isEmpty);
        manager.dispose();
      },
    );

    test(
      'IPC dispatch without onPacketLogged callback does not throw',
      () async {
        final deps = await _buildDeps();
        final manager = BackgroundServiceManager(
          registry: deps.registry,
          beaconing: deps.beaconing,
          tx: deps.tx,
          taskApi: FakeForegroundServiceApi(),
        );

        expect(
          () => manager.debugDispatchTaskData({
            'type': 'beacon_sent',
            'ts': 123,
            'aprs_line': 'X>Y:=test',
          }),
          returnsNormally,
        );
        manager.dispose();
      },
    );
  });

  group('BackgroundServiceManager — non-Android platform', () {
    testWidgets(
      'requestStartService returns false on non-Android (test runs on Linux)',
      (tester) async {
        final deps = await _buildDeps();
        final fake = FakeForegroundServiceApi();
        final manager = BackgroundServiceManager(
          registry: deps.registry,
          beaconing: deps.beaconing,
          tx: deps.tx,
          taskApi: fake,
        );

        late bool result;
        await tester.pumpWidget(
          Builder(
            builder: (ctx) {
              return const SizedBox.shrink();
            },
          ),
        );

        final ctx = tester.element(find.byType(SizedBox));
        result = await manager.requestStartService(ctx);

        expect(result, isFalse);
        expect(fake.startCallCount, 0);
        expect(manager.state, BackgroundServiceState.stopped);
        manager.dispose();
      },
    );

    test('stopService is a no-op on non-Android', () async {
      final deps = await _buildDeps();
      final fake = FakeForegroundServiceApi();
      final manager = BackgroundServiceManager(
        registry: deps.registry,
        beaconing: deps.beaconing,
        tx: deps.tx,
        taskApi: fake,
      );

      await manager.stopService();

      expect(fake.stopCallCount, 0);
      expect(manager.state, BackgroundServiceState.stopped);
      manager.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // Issue #99 — state-desync recovery
  // ---------------------------------------------------------------------------
  group('BackgroundServiceManager — OS state reconciliation (Issue #99)', () {
    test(
      'reconcile transitions running → stopped when OS reports FGS gone',
      () async {
        final deps = await _buildDeps();
        final fake = FakeForegroundServiceApi();
        final manager = BackgroundServiceManager(
          registry: deps.registry,
          beaconing: deps.beaconing,
          tx: deps.tx,
          taskApi: fake,
        );

        // Simulate the bug: BSM thinks the FGS is alive, but the OS killed it.
        manager.setStateForTest(BackgroundServiceState.running);
        fake.runningOverride = false;

        await manager.debugReconcileWithOs();

        expect(fake.isRunningCallCount, 1);
        expect(manager.state, BackgroundServiceState.stopped);
        manager.dispose();
      },
    );

    test('reconcile leaves state alone when OS confirms FGS running', () async {
      final deps = await _buildDeps();
      final fake = FakeForegroundServiceApi();
      final manager = BackgroundServiceManager(
        registry: deps.registry,
        beaconing: deps.beaconing,
        tx: deps.tx,
        taskApi: fake,
      );

      manager.setStateForTest(BackgroundServiceState.running);
      fake.runningOverride = true;

      await manager.debugReconcileWithOs();

      expect(fake.isRunningCallCount, 1);
      expect(manager.state, BackgroundServiceState.running);
      manager.dispose();
    });

    test(
      'reconcile is a no-op (and does not poll OS) when state is stopped',
      () async {
        final deps = await _buildDeps();
        final fake = FakeForegroundServiceApi();
        final manager = BackgroundServiceManager(
          registry: deps.registry,
          beaconing: deps.beaconing,
          tx: deps.tx,
          taskApi: fake,
        );

        // _state starts as stopped — reconcile should short-circuit before
        // polling the OS, so listener-tick churn doesn't drive isRunningService
        // calls in the common case.
        fake.runningOverride = false;

        await manager.debugReconcileWithOs();

        expect(fake.isRunningCallCount, 0);
        expect(manager.state, BackgroundServiceState.stopped);
        manager.dispose();
      },
    );

    test(
      'reconcile transitions reconnecting → stopped when OS reports FGS gone',
      () async {
        final deps = await _buildDeps();
        final fake = FakeForegroundServiceApi();
        final manager = BackgroundServiceManager(
          registry: deps.registry,
          beaconing: deps.beaconing,
          tx: deps.tx,
          taskApi: fake,
        );

        // `reconnecting` is also covered by `isRunning` — the bug was reported
        // against this state too (the FGS could die mid-reconnect retry).
        manager.setStateForTest(BackgroundServiceState.reconnecting);
        fake.runningOverride = false;

        await manager.debugReconcileWithOs();

        expect(manager.state, BackgroundServiceState.stopped);
        manager.dispose();
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Issue #99 — BeaconingService.startBeaconing refreshes lastBeaconAt
  // ---------------------------------------------------------------------------
  group('BeaconingService — startBeaconing refreshes lastBeaconAt', () {
    test('startBeaconing overwrites a stale _lastBeaconAt (Bug C)', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = StationSettingsService(
        prefs,
        store: FakeSecureCredentialStore(),
      );
      // Manual location source so beaconNow does not need GPS — the test
      // platform has no geolocator implementation.
      await settings.setLocationSource(LocationSource.manual);
      await settings.setManualPosition(40.0, -74.0);
      await settings.setCallsign('NOCALL');

      final registry = ConnectionRegistry();
      final tx = TxService(registry, settings);
      final beaconing = BeaconingService(settings, tx);
      await beaconing.setMode(BeaconMode.auto);

      // Set up the bug precondition: a stale _lastBeaconAt from a prior
      // session. The cleanest way to plant one without exposing internals
      // is to send a beacon, stop, then verify the stale timestamp persists
      // until the next startBeaconing() call.
      await beaconing.beaconNow();
      final firstBeaconAt = beaconing.lastBeaconAt;
      expect(firstBeaconAt, isNotNull);

      // Simulate time passing — yield enough microtasks that DateTime.now()
      // advances past `firstBeaconAt` in millisecond resolution.
      await Future<void>.delayed(const Duration(milliseconds: 5));

      // startBeaconing must reset _lastBeaconAt to "now" so the notification
      // body does not lie with a stale "22m ago" value carried over from
      // before the previous stop.
      // ignore: unawaited_futures
      beaconing.startBeaconing();
      // Yield so the synchronous notifyListeners + assignment chain settles
      // (the await on _startPositionStream comes after our line of interest).
      await Future<void>.delayed(Duration.zero);

      final afterStart = beaconing.lastBeaconAt;
      expect(afterStart, isNotNull);
      expect(
        afterStart!.isAfter(firstBeaconAt!),
        isTrue,
        reason:
            'startBeaconing must reset _lastBeaconAt so the notification '
            'body does not lie about the pre-disable timestamp.',
      );

      await beaconing.stopBeaconing();
    });
  });
}
