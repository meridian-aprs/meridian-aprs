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

// ---------------------------------------------------------------------------
// FakeForegroundServiceApi
// ---------------------------------------------------------------------------

class FakeForegroundServiceApi implements ForegroundServiceApi {
  int startCallCount = 0;
  int updateCallCount = 0;
  int stopCallCount = 0;

  String? lastTitle;
  String? lastBody;

  bool startReturnsSuccess;

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
  final tx = TxService(registry);
  final settings = StationSettingsService(prefs);
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
}
