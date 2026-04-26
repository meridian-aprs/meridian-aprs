/// Widget tests for [StationInfoSheet] — verifies the message-capability
/// indicator and the conditional Message button.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meridian_aprs/core/connection/connection_registry.dart';
import 'package:meridian_aprs/core/packet/station.dart';
import 'package:meridian_aprs/services/beaconing_service.dart';
import 'package:meridian_aprs/services/station_service.dart';
import 'package:meridian_aprs/services/station_settings_service.dart';
import 'package:meridian_aprs/services/tx_service.dart';
import 'package:meridian_aprs/ui/widgets/station_info_sheet.dart';

import '../helpers/fake_secure_credential_store.dart';

Future<void> _pumpSheet(WidgetTester tester, {required Station station}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final stationService = StationService();
  final stationSettings = StationSettingsService(
    prefs,
    store: FakeSecureCredentialStore(),
  );
  final registry = ConnectionRegistry();
  final txService = TxService(registry, stationSettings);
  final beaconing = BeaconingService(stationSettings, txService);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<StationService>.value(value: stationService),
        ChangeNotifierProvider<StationSettingsService>.value(
          value: stationSettings,
        ),
        ChangeNotifierProvider<BeaconingService>.value(value: beaconing),
      ],
      child: MaterialApp(
        home: Scaffold(body: StationInfoSheet(station: station)),
      ),
    ),
  );
  await tester.pump();
}

Station _stationWith(MessageCapability capability) => Station(
  callsign: 'W1AW',
  lat: 41.7,
  lon: -72.7,
  rawPacket: '',
  lastHeard: DateTime.now(),
  symbolTable: '/',
  symbolCode: '>',
  comment: '',
  messageCapability: capability,
);

void main() {
  group('StationInfoSheet message capability', () {
    testWidgets('supported station shows Message button + supported tooltip', (
      tester,
    ) async {
      await _pumpSheet(
        tester,
        station: _stationWith(MessageCapability.supported),
      );

      expect(find.text('Message W1AW'), findsOneWidget);
      expect(find.byTooltip('Message-capable'), findsOneWidget);
    });

    testWidgets('unsupported station hides Message button + shows tooltip', (
      tester,
    ) async {
      await _pumpSheet(
        tester,
        station: _stationWith(MessageCapability.unsupported),
      );

      expect(find.text('Message W1AW'), findsNothing);
      expect(find.byTooltip('Not message-capable'), findsOneWidget);
    });

    testWidgets('unknown capability still shows Message button', (
      tester,
    ) async {
      await _pumpSheet(
        tester,
        station: _stationWith(MessageCapability.unknown),
      );

      expect(find.text('Message W1AW'), findsOneWidget);
      expect(find.byTooltip('Messaging support unknown'), findsOneWidget);
    });
  });
}
