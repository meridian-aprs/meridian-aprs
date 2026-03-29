import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:meridian_aprs/theme/theme_controller.dart';
import 'package:meridian_aprs/screens/map_screen.dart';
import 'package:meridian_aprs/services/beaconing_service.dart';
import 'package:meridian_aprs/services/message_service.dart';
import 'package:meridian_aprs/services/station_service.dart';
import 'package:meridian_aprs/services/station_settings_service.dart';
import 'package:meridian_aprs/services/tnc_service.dart';
import 'package:meridian_aprs/services/tx_service.dart';

import 'helpers/fake_transport.dart';

void main() {
  testWidgets('MapScreen renders without throwing', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final themeController = await ThemeController.create();
    final transport = FakeTransport();
    final service = StationService(transport);
    final tncService = TncService(service);
    final txService = TxService(transport, tncService);
    final stationSettings = StationSettingsService(prefs);
    final beaconingService = BeaconingService(stationSettings, txService);
    final messageService = MessageService(stationSettings, txService, service);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeController>.value(value: themeController),
          ChangeNotifierProvider<StationService>.value(value: service),
          ChangeNotifierProvider<TncService>.value(value: tncService),
          ChangeNotifierProvider<TxService>.value(value: txService),
          ChangeNotifierProvider<StationSettingsService>.value(
            value: stationSettings,
          ),
          ChangeNotifierProvider<BeaconingService>.value(
            value: beaconingService,
          ),
          ChangeNotifierProvider<MessageService>.value(value: messageService),
        ],
        child: MaterialApp(
          home: MapScreen(service: service, tncService: tncService),
        ),
      ),
    );

    // Pump a single frame — enough to verify the widget tree builds without
    // throwing. We do not call pumpAndSettle because MapScreen may leave
    // async timers alive.
    await tester.pump();

    // Verify the screen mounted successfully.
    expect(find.byType(MapScreen), findsOneWidget);
  });
}
