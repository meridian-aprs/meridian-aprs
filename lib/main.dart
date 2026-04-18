import 'dart:io' show Platform;

import 'package:http_cache_file_store/http_cache_file_store.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/notification_service.dart';
import 'ui/widgets/in_app_banner_overlay.dart';

import 'config/app_config.dart';
import 'core/connection/aprs_is_connection.dart';
import 'core/connection/ble_connection.dart';
import 'core/connection/connection_registry.dart';
import 'core/connection/serial_connection.dart';
import 'core/packet/aprs_packet.dart' show PacketSource;
import 'core/transport/aprs_is_transport.dart';
import 'map/stadia_tile_provider.dart';
import 'screens/map_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'services/background_service_manager.dart';
import 'services/beaconing_service.dart';
import 'services/ios_background_service.dart';
import 'services/message_service.dart';
import 'services/station_service.dart';
import 'services/station_settings_service.dart';
import 'services/tx_service.dart';
import 'theme/android_theme.dart';
import 'theme/desktop_theme.dart';
import 'theme/ios_theme.dart';
import 'theme/meridian_colors.dart';
import 'theme/theme_controller.dart';

const String _kVersion = '0.1.0';

/// Global navigator key so [NotificationService] can push routes from outside
/// the widget tree (notification taps, inline reply navigation).
final navigatorKey = GlobalKey<NavigatorState>();

/// Maps a [ConnectionType] to the [PacketSource] tag used in [StationService].
PacketSource _packetSourceFor(ConnectionType type) => switch (type) {
  ConnectionType.aprsIs => PacketSource.aprsIs,
  ConnectionType.bleTnc => PacketSource.bleTnc,
  ConnectionType.serialTnc => PacketSource.serialTnc,
};

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

  // Initialise foreground task communication port before any isolates start.
  // Safe to call on all platforms (no-op on non-Android).
  FlutterForegroundTask.initCommunicationPort();

  // Initialise Android notification channel options for the background service.
  BackgroundServiceManager.initOptions();

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

  // ---------------------------------------------------------------------------
  // Build connections
  // ---------------------------------------------------------------------------

  final aprsIsTransport = AprsIsTransport(
    loginLine:
        'user $effectiveCallsign$ssidSuffix pass $effectivePasscode vers meridian-aprs $_kVersion\r\n',
    filterLine: AprsIsConnection.defaultFilterLine(mapLat, mapLon),
  );
  final aprsIsConn = AprsIsConnection(aprsIsTransport);

  // Platform-conditional TNC connections.
  BleConnection? bleConn;
  SerialConnection? serialConn;

  if (!kIsWeb) {
    if (Platform.isAndroid || Platform.isIOS) {
      bleConn = BleConnection();
    }
    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      serialConn = SerialConnection();
    }
  }

  final registry = ConnectionRegistry();
  registry.register(aprsIsConn);
  if (bleConn != null) registry.register(bleConn);
  if (serialConn != null) registry.register(serialConn);

  // Load persisted settings (beaconing toggles, serial config) for all
  // connections before the first frame.
  await registry.loadAllSettings();

  // ---------------------------------------------------------------------------
  // Build service layer
  // ---------------------------------------------------------------------------

  final service = StationService();
  await service.loadPersistedHistory(prefs);

  // Wire ingestLine subscriptions: each connection's decoded text lines are
  // forwarded to StationService with the correct source tag.
  for (final conn in registry.all) {
    conn.lines.listen(
      (line) => service.ingestLine(line, source: _packetSourceFor(conn.type)),
      onError: (Object e, StackTrace st) {
        debugPrint('[${conn.id}] stream error: $e\n$st');
      },
    );
  }

  // Start APRS-IS connection on launch.
  aprsIsConn.connect().catchError((Object e) {
    debugPrint('APRS-IS connection failed: $e');
  });

  final stationSettings = StationSettingsService(prefs);
  final txService = TxService(registry);
  await txService.loadPersistedPreference();

  final beaconingService = BeaconingService(
    stationSettings,
    txService,
    onBeaconSent: (line) =>
        service.ingestLine(line, source: PacketSource.aprsIs),
  );
  await beaconingService.loadPersistedSettings();

  final messageService = MessageService(stationSettings, txService, service);
  await messageService.loadHistory();

  final bannerController = InAppBannerController();
  final notificationService = NotificationService(
    messageService: messageService,
    prefs: prefs,
    navigatorKey: navigatorKey,
    bannerController: bannerController,
  );
  await notificationService.initialize();

  // Tile cache: persist tiles to disk for 30 days so repeated sessions don't
  // re-fetch the same tiles and burn through Stadia Maps API credits.
  final cacheDir = await getTemporaryDirectory();
  final tileProvider = StadiaTileProvider(
    apiKey: AppConfig.stadiaMapsApiKey,
    cacheStore: FileCacheStore('${cacheDir.path}/meridian_tiles'),
  );

  final bgServiceManager = BackgroundServiceManager(
    registry: registry,
    beaconing: beaconingService,
    tx: txService,
  );

  // ---------------------------------------------------------------------------
  // iOS background service (v0.9)
  // ---------------------------------------------------------------------------
  // iOS keeps the process alive via UIBackgroundModes (voip, bluetooth-central,
  // location) so no separate background isolate is needed. IosBackgroundService
  // manages the Live Activity and background location permission signalling.

  IosBackgroundService? iosBackgroundService;
  if (!kIsWeb && Platform.isIOS) {
    iosBackgroundService = IosBackgroundService();
    await iosBackgroundService.initialize();

    registry.addListener(() async {
      final content = LiveActivityContent.fromRegistryAndBeaconing(
        registry,
        beaconingService,
      );
      await iosBackgroundService!.onConnectionsChanged(content);
    });

    beaconingService.addListener(() async {
      final content = LiveActivityContent.fromRegistryAndBeaconing(
        registry,
        beaconingService,
      );
      await iosBackgroundService!.onBeaconingChanged(
        beaconingService.mode,
        content,
      );
    });
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: themeController),
        ChangeNotifierProvider<StationService>.value(value: service),
        ChangeNotifierProvider<ConnectionRegistry>.value(value: registry),
        ChangeNotifierProvider<StationSettingsService>.value(
          value: stationSettings,
        ),
        ChangeNotifierProvider<TxService>.value(value: txService),
        ChangeNotifierProvider<BeaconingService>.value(value: beaconingService),
        ChangeNotifierProvider<MessageService>.value(value: messageService),
        ChangeNotifierProvider<BackgroundServiceManager>.value(
          value: bgServiceManager,
        ),
        ChangeNotifierProvider<NotificationService>.value(
          value: notificationService,
        ),
        ChangeNotifierProvider<InAppBannerController>.value(
          value: bannerController,
        ),
        if (iosBackgroundService != null)
          ChangeNotifierProvider<IosBackgroundService>.value(
            value: iosBackgroundService,
          ),
      ],
      child: MeridianApp(
        onboardingComplete: onboardingComplete,
        userCallsign: effectiveCallsign,
        userSsid: userSsid,
        mapLat: mapLat,
        mapLon: mapLon,
        mapZoom: mapZoom,
        service: service,
        tileProvider: tileProvider,
        bannerController: bannerController,
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
    required this.tileProvider,
    required this.bannerController,
  });

  final bool onboardingComplete;
  final String userCallsign;
  final int userSsid;
  final double mapLat;
  final double mapLon;
  final double mapZoom;
  final StationService service;
  final StadiaTileProvider tileProvider;
  final InAppBannerController bannerController;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ThemeController>();

    Widget homeWidget() => InAppBannerOverlay(
      controller: bannerController,
      child: onboardingComplete
          ? MapScreen(
              service: service,
              tileProvider: tileProvider,
              callsign: userCallsign,
              ssid: userSsid,
              initialLat: mapLat,
              initialLon: mapLon,
              initialZoom: mapZoom,
            )
          : const OnboardingScreen(),
    );

    if (!kIsWeb && Platform.isIOS) {
      final brightness = _resolveIosBrightness(controller.themeMode);
      return CupertinoApp(
        title: 'Meridian APRS',
        navigatorKey: navigatorKey,
        theme: buildIosTheme(
          brightness: brightness,
          primaryColor: controller.seedColor,
        ),
        debugShowCheckedModeBanner: false,
        // CupertinoApp does not provide ScaffoldMessenger; add one so that
        // Material SnackBars work on all routes under this navigator.
        builder: (context, child) => ScaffoldMessenger(child: child!),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', 'US')],
        home: homeWidget(),
      );
    }

    if (!kIsWeb &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      final themes = buildDesktopTheme(seedColor: MeridianColors.primary);
      return MaterialApp(
        title: 'Meridian APRS',
        navigatorKey: navigatorKey,
        themeMode: controller.themeMode,
        theme: themes.light,
        darkTheme: themes.dark,
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', 'US')],
        home: homeWidget(),
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
          navigatorKey: navigatorKey,
          themeMode: controller.themeMode,
          theme: themes.light,
          darkTheme: themes.dark,
          home: homeWidget(),
        );
      },
    );
  }
}
