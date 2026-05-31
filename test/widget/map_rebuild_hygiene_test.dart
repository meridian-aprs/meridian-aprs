import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meridian_aprs/core/connection/connection_registry.dart';
import 'package:meridian_aprs/screens/map_screen.dart';
import 'package:meridian_aprs/services/background_service_manager.dart';
import 'package:meridian_aprs/services/beaconing_service.dart';
import 'package:meridian_aprs/services/bulletin_service.dart';
import 'package:meridian_aprs/services/bulletin_subscription_service.dart';
import 'package:meridian_aprs/services/group_subscription_service.dart';
import 'package:meridian_aprs/services/message_service.dart';
import 'package:meridian_aprs/services/station_service.dart';
import 'package:meridian_aprs/services/station_settings_service.dart';
import 'package:meridian_aprs/services/tx_service.dart';
import 'package:meridian_aprs/theme/theme_controller.dart';
import 'package:meridian_aprs/ui/layout/meridian_map.dart';

import '../helpers/fake_meridian_connection.dart';
import '../helpers/fake_secure_credential_store.dart';
import '../helpers/test_database.dart';

/// Regression guard for Issue #51: feeding packets into [StationService] must
/// rebuild only the map's marker layer — never the surrounding scaffold chrome.
///
/// How the guard works: [MeridianMap] is constructed inside each scaffold's
/// `build()`. If a scaffold (or [MapScreen]) ever rebuilds in response to a
/// per-packet notify — e.g. someone adds a `context.watch<StationService>()`
/// to the chrome — a *new* [MeridianMap] widget instance is created. So a
/// stable widget identity across many packets proves the chrome did not
/// rebuild, while the [MarkerLayer]'s growing marker count proves the leaf
/// (driven by the `ValueNotifier<MapRenderData>`) still updates.
///
/// The marker rebuild flows through MapScreen's 300 ms debounce, so each pump
/// advances past it before sampling.
void main() {
  testWidgets(
    'packets rebuild the marker layer but not the scaffold chrome (#51)',
    (WidgetTester tester) async {
      // Force a mobile layout (< 600 px) so MobileScaffold is selected.
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final themeController = await ThemeController.create();

      final registry = ConnectionRegistry();
      registry.register(
        FakeMeridianConnection(
          id: 'aprs_is',
          displayName: 'APRS-IS',
          type: ConnectionType.aprsIs,
        ),
      );

      final db = buildTestDatabase();
      final service = StationService(
        stationDao: db.stationDao,
        packetDao: db.packetDao,
      );
      addTearDown(() async {
        await service.stop();
        await db.close();
      });
      final stationSettings = StationSettingsService(
        prefs,
        store: FakeSecureCredentialStore(),
      );
      final txService = TxService(registry, stationSettings);
      final beaconingService = BeaconingService(stationSettings, txService);
      final groupSubs = GroupSubscriptionService(prefs: prefs);
      await groupSubs.load();
      final bulletinSubs = BulletinSubscriptionService(prefs: prefs);
      await bulletinSubs.load();
      final bulletins = BulletinService(
        subscriptions: bulletinSubs,
        bulletinDao: db.bulletinDao,
        prefs: prefs,
      );
      await bulletins.load();
      final messageService = MessageService(
        stationSettings,
        txService,
        service,
        groupSubscriptions: groupSubs,
        bulletins: bulletins,
        messageDao: db.messageDao,
      );
      final bgServiceManager = BackgroundServiceManager(
        registry: registry,
        beaconing: beaconingService,
        tx: txService,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeController>.value(
              value: themeController,
            ),
            ChangeNotifierProvider<StationService>.value(value: service),
            ChangeNotifierProvider<ConnectionRegistry>.value(value: registry),
            ChangeNotifierProvider<TxService>.value(value: txService),
            ChangeNotifierProvider<StationSettingsService>.value(
              value: stationSettings,
            ),
            ChangeNotifierProvider<BeaconingService>.value(
              value: beaconingService,
            ),
            ChangeNotifierProvider<MessageService>.value(value: messageService),
            ChangeNotifierProvider<BackgroundServiceManager>.value(
              value: bgServiceManager,
            ),
          ],
          child: MaterialApp(home: MapScreen(service: service)),
        ),
      );
      await tester.pump();

      // Seed one station and let the marker debounce settle.
      await service.ingestLine('W1AW>APMDN0:!4903.50N/07201.75W>seed');
      await tester.pump(const Duration(milliseconds: 350));

      MeridianMap currentMap() =>
          tester.widget<MeridianMap>(find.byType(MeridianMap));
      int markerCount() =>
          tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.length;

      final mapBefore = currentMap();
      final markersBefore = markerCount();
      expect(markersBefore, 1, reason: 'seed station should produce 1 marker');

      // Feed several more packets from distinct, widely-separated callsigns so
      // they do not cluster into a single marker at the initial zoom.
      await service.ingestLine('W2XY>APMDN0:!3234.00N/08901.00W>two');
      await service.ingestLine('N0FFF>APMDN0:!4012.00N/10001.00W>three');
      await tester.pump(const Duration(milliseconds: 350));

      final mapAfter = currentMap();
      final markersAfter = markerCount();

      // Chrome did not rebuild: same MeridianMap widget instance survives the
      // packet burst (MapScreen.build / scaffold.build never re-ran).
      expect(
        identical(mapBefore, mapAfter),
        isTrue,
        reason:
            'MeridianMap was reconstructed — a scaffold rebuilt on packet '
            'receipt. Did a per-packet context.watch creep into the chrome?',
      );

      // Leaf did update: the marker layer grew via the render-data notifier.
      expect(
        markersAfter,
        greaterThan(markersBefore),
        reason: 'marker layer should reflect the newly ingested stations',
      );
      expect(markersAfter, 3);
    },
  );
}
