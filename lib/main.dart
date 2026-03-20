import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/map_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'ui/theme/app_theme.dart';
import 'ui/theme/theme_provider.dart';

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

  runApp(
    ChangeNotifierProvider<ThemeProvider>.value(
      value: themeProvider,
      child: MeridianApp(
        onboardingComplete: onboardingComplete,
        userCallsign: userCallsign,
        userPasscode: userPasscode,
        userSsid: userSsid,
        mapLat: mapLat,
        mapLon: mapLon,
        mapZoom: mapZoom,
      ),
    ),
  );
}

class MeridianApp extends StatelessWidget {
  const MeridianApp({
    super.key,
    required this.onboardingComplete,
    this.userCallsign = '',
    this.userPasscode = '',
    this.userSsid = 0,
    this.mapLat = 39.0,
    this.mapLon = -77.0,
    this.mapZoom = 9.0,
  });

  final bool onboardingComplete;
  final String userCallsign;
  final String userPasscode;
  final int userSsid;
  final double mapLat;
  final double mapLon;
  final double mapZoom;

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
              callsign: userCallsign.isNotEmpty ? userCallsign : 'NOCALL',
              passcode: userPasscode,
              ssid: userSsid,
              initialLat: mapLat,
              initialLon: mapLon,
              initialZoom: mapZoom,
            )
          : const OnboardingScreen(),
    );
  }
}
