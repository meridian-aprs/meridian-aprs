import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/station_service.dart';
import '../../services/station_settings_service.dart';
import '../../ui/utils/platform_route.dart';
import '../map_screen.dart';
import 'pages/beaconing_page.dart';
import 'pages/callsign_page.dart';
import 'pages/connection_page.dart';
import 'pages/license_page.dart' as license_page;
import 'pages/location_page.dart';
import 'pages/station_identity_page.dart';
import 'pages/welcome_page.dart';

/// New v0.12 onboarding flow — step-controller variant.
///
/// Replaces the old 3-page PageView with a 5–7 step adaptive flow:
///
///   Welcome → License → [Callsign (licensed only)] → Location →
///   StationIdentity → Connection → [Beaconing (connection configured)]
///
/// Steps are assembled dynamically based on user choices. Navigation uses
/// [AnimatedSwitcher] with a directional slide so there is no swipe gesture —
/// only Next/Back buttons. A [LinearProgressIndicator] in the AppBar tracks
/// progress through the current step count.
///
/// On completion or skip, `onboarding_complete` is persisted and the user is
/// pushed to [MapScreen].
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static const _prefKey = 'onboarding_complete';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

/// Logical step identifiers used to build the active step list.
enum _StepId {
  welcome,
  license,
  callsign,
  location,
  stationIdentity,
  connection,
  beaconing,
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _currentStep = 0;

  /// Whether the Connection step resulted in a successfully configured
  /// connection. Controls inclusion of the Beaconing step.
  bool _connectionConfigured = false;

  /// Direction of the last navigation; +1 = forward, -1 = backward.
  int _direction = 1;

  /// Key used to force [AnimatedSwitcher] to treat every step as a new widget.
  int _pageKey = 0;

  List<_StepId> _buildSteps(bool isLicensed) {
    return [
      _StepId.welcome,
      _StepId.license,
      if (isLicensed) _StepId.callsign,
      _StepId.location,
      _StepId.stationIdentity,
      _StepId.connection,
      if (_connectionConfigured) _StepId.beaconing,
    ];
  }

  void _advance() {
    final steps = _buildSteps(_isLicensed);
    if (_currentStep < steps.length - 1) {
      setState(() {
        _direction = 1;
        _pageKey++;
        _currentStep++;
      });
    } else {
      _finish();
    }
  }

  void _back() {
    if (_currentStep > 0) {
      setState(() {
        _direction = -1;
        _pageKey++;
        _currentStep--;
      });
    }
  }

  bool get _isLicensed => context.read<StationSettingsService>().isLicensed;

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(OnboardingScreen._prefKey, true);
    if (!mounted) return;
    _navigateToMap();
  }

  Future<void> _skip() => _finish();

  Future<void> _navigateToMap() async {
    if (!mounted) return;
    final service = context.read<StationService>();
    final settings = context.read<StationSettingsService>();
    final callsign = settings.callsign.isNotEmpty
        ? settings.callsign
        : 'NOCALL';

    // Restore the last map viewport so the user lands where they left off.
    // If no saved position exists (first-ever launch), the defaults in
    // MapScreen are used (39° N, 77° W, zoom 9 — continental US).
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final lat = prefs.getDouble('map_last_lat') ?? 39.0;
    final lon = prefs.getDouble('map_last_lon') ?? -77.0;
    final zoom = prefs.getDouble('map_last_zoom') ?? 9.0;

    Navigator.pushReplacement(
      context,
      buildPlatformRoute(
        (_) => MapScreen(
          service: service,
          callsign: callsign,
          ssid: settings.ssid,
          initialLat: lat,
          initialLon: lon,
          initialZoom: zoom,
        ),
      ),
    );
  }

  void _onConnectionResult(bool configured) {
    setState(() => _connectionConfigured = configured);
  }

  Widget _buildPage(_StepId stepId) {
    switch (stepId) {
      case _StepId.welcome:
        return WelcomePage(onNext: _advance, onSkip: _skip);
      case _StepId.license:
        return license_page.LicensePage(onNext: _advance);
      case _StepId.callsign:
        return CallsignPage(onNext: _advance, onBack: _back);
      case _StepId.location:
        return LocationPage(onNext: _advance, onBack: _back);
      case _StepId.stationIdentity:
        return StationIdentityPage(onNext: _advance, onBack: _back);
      case _StepId.connection:
        return ConnectionPage(
          onNext: _advance,
          onBack: _back,
          onConnectionResult: _onConnectionResult,
        );
      case _StepId.beaconing:
        return BeaconingPage(onFinish: _finish, onBack: _back);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Read isLicensed from settings — rebuilds when setIsLicensed is called.
    final isLicensed = context.watch<StationSettingsService>().isLicensed;
    final steps = _buildSteps(isLicensed);

    // Clamp current step in case the step list shrinks (e.g. license toggled).
    final safeStep = _currentStep.clamp(0, steps.length - 1);
    if (safeStep != _currentStep) {
      // Schedule correction for after this build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _currentStep = safeStep);
      });
    }

    final currentStepId = steps[safeStep];
    final progress = steps.length > 1
        ? safeStep / (steps.length - 1).toDouble()
        : 1.0;
    final showBackButton = safeStep > 0;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: showBackButton
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back)
            : null,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
          ),
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animation) {
          final offsetTween = Tween<Offset>(
            begin: Offset(_direction.toDouble(), 0),
            end: Offset.zero,
          );
          final slideAnimation = offsetTween.animate(
            CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          );
          return SlideTransition(position: slideAnimation, child: child);
        },
        child: KeyedSubtree(
          key: ValueKey(_pageKey),
          child: _buildPage(currentStepId),
        ),
      ),
    );
  }
}
