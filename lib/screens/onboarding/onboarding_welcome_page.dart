import 'package:flutter/material.dart';

/// First onboarding page — welcome and value proposition.
///
/// The user can proceed through setup with "Get Started" or skip directly to
/// the map if they are an experienced APRS operator.
class OnboardingWelcomePage extends StatelessWidget {
  const OnboardingWelcomePage({
    super.key,
    required this.onGetStarted,
    required this.onSkip,
  });

  /// Advance to the next onboarding page.
  final VoidCallback onGetStarted;

  /// Mark onboarding complete and navigate directly to the map.
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            Icon(Icons.radio, size: 80, color: colorScheme.primary),
            const SizedBox(height: 24),
            Text(
              'Meridian',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'APRS for the Modern Ham.',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Text(
              'Meridian connects you to the APRS network — live station '
              'tracking, messaging, and beaconing from one app.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onGetStarted,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Get Started'),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onSkip,
              child: const Text('I know APRS, skip setup'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
