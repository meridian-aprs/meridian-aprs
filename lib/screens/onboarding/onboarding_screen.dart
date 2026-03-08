import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../map_screen.dart';
import 'onboarding_callsign_page.dart';
import 'onboarding_connect_page.dart';
import 'onboarding_welcome_page.dart';

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

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _markCompleteAndNavigate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(OnboardingScreen._prefKey, true);
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MapScreen()),
      );
    }
  }

  void _nextPage() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
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
          OnboardingCallsignPage(onNext: _nextPage),
          OnboardingConnectPage(onStartListening: _markCompleteAndNavigate),
        ],
      ),
    );
  }
}
