import 'package:flutter/material.dart';

import '../../../ui/widgets/meridian_wordmark.dart';

/// Onboarding step 1 — brand splash with "Get Started" and "Skip setup".
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key, required this.onNext, required this.onSkip});

  /// Advance to the next onboarding step.
  final VoidCallback onNext;

  /// Skip all onboarding and go directly to the map.
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
            const MeridianWordmark.stacked(height: 200),
            const SizedBox(height: 24),
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
              child: FilledButton(
                onPressed: onNext,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Get Started'),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: onSkip, child: const Text('Skip setup')),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
