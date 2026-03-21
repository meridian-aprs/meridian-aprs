import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/transport/aprs_is_transport.dart';
import '../../services/station_service.dart';
import '../../services/tnc_service.dart';
import '../map_screen.dart';
import 'onboarding_callsign_page.dart';
import 'onboarding_connect_page.dart';
import 'onboarding_welcome_page.dart';

const String _kVersion = '0.1.0';

/// Three-page onboarding flow shown on first launch.
///
/// Shown when SharedPreferences key `'onboarding_complete'` is false or
/// absent. The flow is skippable from page 1.
///
/// On completion or skip, `'onboarding_complete'` is set to `true` and the
/// user is taken to [MapScreen] via [Navigator.pushReplacement].
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static const _prefKey = 'onboarding_complete';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();

  String _callsign = '';
  int _ssid = 0;
  String _passcode = '';
  int _connectionMethod = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _markCompleteAndNavigate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(OnboardingScreen._prefKey, true);
    if (_callsign.isNotEmpty) {
      await prefs.setString('user_callsign', _callsign);
    }
    await prefs.setInt('user_ssid', _ssid);
    await prefs.setString('user_passcode', _passcode);
    // connection_method is persisted for future use.
    // 0 = APRS-IS (only active transport). BLE (v0.4) and USB (v0.3) are not
    // yet implemented; transport selection will be wired here when they land.
    await prefs.setInt('connection_method', _connectionMethod);

    final effectiveCallsign = _callsign.isNotEmpty ? _callsign : 'NOCALL';
    final ssidSuffix = _ssid > 0 ? '-$_ssid' : '';
    final effectivePasscode = _passcode.isEmpty ? '-1' : _passcode;
    final mapLat = prefs.getDouble('map_last_lat') ?? 39.0;
    final mapLon = prefs.getDouble('map_last_lon') ?? -77.0;

    final transport = AprsIsTransport(
      loginLine:
          'user $effectiveCallsign$ssidSuffix pass $effectivePasscode vers meridian-aprs $_kVersion\r\n',
      filterLine:
          '#filter r/${mapLat.toStringAsFixed(1)}/${mapLon.toStringAsFixed(1)}/100\r\n',
    );
    final service = StationService(transport);
    final tncService = TncService(service);

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MapScreen(
            service: service,
            tncService: tncService,
            callsign: effectiveCallsign,
            ssid: _ssid,
            initialLat: mapLat,
            initialLon: mapLon,
          ),
        ),
      );
    }
  }

  void _nextPage() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  void _onCallsignNext(String callsign, int ssid, String passcode) {
    _callsign = callsign;
    _ssid = ssid;
    _passcode = passcode;
    _nextPage();
  }

  void _onStartListening(int connectionMethod) {
    _connectionMethod = connectionMethod;
    _markCompleteAndNavigate();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          OnboardingWelcomePage(
            onGetStarted: _nextPage,
            onSkip: _markCompleteAndNavigate,
          ),
          OnboardingCallsignPage(onNext: _onCallsignNext),
          OnboardingConnectPage(onStartListening: _onStartListening),
        ],
      ),
    );
  }
}
