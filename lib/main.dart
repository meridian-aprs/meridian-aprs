import 'dart:io' show Platform;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/transport/aprs_is_transport.dart';
import 'screens/map_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'services/station_service.dart';
import 'services/tnc_service.dart';
import 'theme/android_theme.dart';
import 'theme/ios_theme.dart';
import 'theme/theme_controller.dart';

const String _kVersion = '0.1.0';

/// Resolves the active [Brightness] from [ThemeMode] for [CupertinoApp].
///
/// [ThemeMode.system] reads [WidgetsBinding.instance.platformDispatcher.platformBrightness]
/// directly. Full reactive brightness for [ThemeMode.system] will be verified
/// during iOS simulator testing.
Brightness _resolveIosBrightness(ThemeMode mode) {
  if (mode == ThemeMode.light) return Brightness.light;
  if (mode == ThemeMode.dark) return Brightness.dark;
  return WidgetsBinding.instance.platformDispatcher.platformBrightness;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load theme preference and onboarding state before the first frame.
  final themeController = await ThemeController.create();
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
        ChangeNotifierProvider<ThemeController>.value(value: themeController),
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
    final controller = context.watch<ThemeController>();

    if (!kIsWeb && Platform.isIOS) {
      final brightness = _resolveIosBrightness(controller.themeMode);
      return CupertinoApp(
        title: 'Meridian APRS',
        theme: buildIosTheme(brightness: brightness),
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', 'US')],
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

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        if (lightDynamic != null) controller.reportDynamicColorAvailable();

        final themes = buildAndroidTheme(
          dynamicLight: controller.useDynamicColor ? lightDynamic : null,
          dynamicDark: controller.useDynamicColor ? darkDynamic : null,
          seedColor: controller.seedColor,
        );

        return MaterialApp(
          title: 'Meridian APRS',
          themeMode: controller.themeMode,
          theme: themes.light,
          darkTheme: themes.dark,
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
      },
    );
  }
}
