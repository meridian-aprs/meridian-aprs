import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/transport/aprs_is_transport.dart';
import 'screens/map_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'services/station_service.dart';
import 'services/tnc_service.dart';
import 'ui/theme/app_theme.dart';
import 'ui/theme/theme_provider.dart';

const String _kVersion = '0.1.0';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load theme preference and onboarding state before the first frame.
  final themeProvider = await ThemeProvider.create();
  final prefs = await SharedPreferences.getInstance();
  final onboardingComplete = prefs.getBool('onboarding_complete') ?? false;
  final userCallsign = prefs.getString('user_callsign') ?? '';
  final userPasscode = prefs.getString('user_passcode') ?? '';
  final userSsid = prefs.getInt('user_ssid') ?? 0;
  final mapLat = prefs.getDouble('map_last_lat') ?? 39.0;
  final mapLon = prefs.getDouble('map_last_lon') ?? -77.0;
  final mapZoom = prefs.getDouble('map_last_zoom') ?? 9.0;

  final effectiveCallsign = userCallsign.isNotEmpty ? userCallsign : 'NOCALL';
  final ssidSuffix = userSsid > 0 ? '-$userSsid' : '';
  final effectivePasscode = userPasscode.isEmpty ? '-1' : userPasscode;

  final transport = AprsIsTransport(
    loginLine:
        'user $effectiveCallsign$ssidSuffix pass $effectivePasscode vers meridian-aprs $_kVersion\r\n',
    filterLine:
        '#filter r/${mapLat.toStringAsFixed(1)}/${mapLon.toStringAsFixed(1)}/100\r\n',
  );
  final service = StationService(transport);
  final tncService = TncService(service);
  await tncService.loadPersistedConfig();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ChangeNotifierProvider<TncService>.value(value: tncService),
      ],
      child: MeridianApp(
        onboardingComplete: onboardingComplete,
        userCallsign: effectiveCallsign,
        userSsid: userSsid,
        mapLat: mapLat,
        mapLon: mapLon,
        mapZoom: mapZoom,
        service: service,
        tncService: tncService,
      ),
    ),
  );
}

class MeridianApp extends StatelessWidget {
  const MeridianApp({
    super.key,
    required this.onboardingComplete,
    this.userCallsign = '',
    this.userSsid = 0,
    this.mapLat = 39.0,
    this.mapLon = -77.0,
    this.mapZoom = 9.0,
    required this.service,
    required this.tncService,
  });

  final bool onboardingComplete;
  final String userCallsign;
  final int userSsid;
  final double mapLat;
  final double mapLon;
  final double mapZoom;
  final StationService service;
  final TncService tncService;

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp(
      title: 'Meridian APRS',
      themeMode: themeProvider.themeMode,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: onboardingComplete
          ? MapScreen(
              service: service,
              tncService: tncService,
              callsign: userCallsign,
              ssid: userSsid,
              initialLat: mapLat,
              initialLon: mapLon,
              initialZoom: mapZoom,
            )
          : const OnboardingScreen(),
    );
  }
}
