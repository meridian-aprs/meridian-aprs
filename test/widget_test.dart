import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:meridian_aprs/core/connection/connection_registry.dart';
import 'package:meridian_aprs/theme/theme_controller.dart';
import 'package:meridian_aprs/screens/map_screen.dart';
import 'package:meridian_aprs/services/background_service_manager.dart';
import 'package:meridian_aprs/services/beaconing_service.dart';
import 'package:meridian_aprs/services/message_service.dart';
import 'package:meridian_aprs/services/station_service.dart';
import 'package:meridian_aprs/services/station_settings_service.dart';
import 'package:meridian_aprs/services/tx_service.dart';

import 'helpers/fake_meridian_connection.dart';

void main() {
  testWidgets('MapScreen renders without throwing', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final themeController = await ThemeController.create();

    // Connection registry with a fake APRS-IS connection.
    final registry = ConnectionRegistry();
    final aprsIsConn = FakeMeridianConnection(
      id: 'aprs_is',
      displayName: 'APRS-IS',
      type: ConnectionType.aprsIs,
    );
    registry.register(aprsIsConn);

    final service = StationService();
    final txService = TxService(registry);
    final stationSettings = StationSettingsService(prefs);
    final beaconingService = BeaconingService(stationSettings, txService);
    final messageService = MessageService(stationSettings, txService, service);
    final bgServiceManager = BackgroundServiceManager(
      registry: registry,
      beaconing: beaconingService,
      tx: txService,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeController>.value(value: themeController),
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

    expect(find.byType(MapScreen), findsOneWidget);
  });
}
