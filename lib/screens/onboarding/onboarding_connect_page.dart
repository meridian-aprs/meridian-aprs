import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../ui/theme/app_theme.dart';

/// Third onboarding page — connection method selection.
///
/// Presents three connection options as tappable cards. BLE and USB options
/// are stub-only at this milestone. "Start Listening" persists the onboarding
/// completion flag and navigates to the map.
class OnboardingConnectPage extends StatefulWidget {
  const OnboardingConnectPage({super.key, required this.onStartListening});

  /// Called when the user taps "Start Listening".
  /// Provides the selected connection method index (0=APRS-IS, 1=BLE, 2=USB).
  final void Function(int connectionMethod) onStartListening;

  @override
  State<OnboardingConnectPage> createState() => _OnboardingConnectPageState();
}

class _OnboardingConnectPageState extends State<OnboardingConnectPage> {
  int _selectedOption =
      0; // 0=APRS-IS only — BLE/USB coming in future milestones

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connect',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose how Meridian connects to the APRS network.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            _OptionCard(
              index: 0,
              selectedIndex: _selectedOption,
              icon: Icons.wifi,
              title: 'APRS-IS',
              subtitle: 'Connect via internet. No hardware required.',
              dimmed: false,
              onTap: () => setState(() => _selectedOption = 0),
            ),
            const SizedBox(height: 12),
            _OptionCard(
              index: 1,
              selectedIndex: _selectedOption,
              icon: Icons.bluetooth,
              title: 'BLE TNC',
              subtitle: 'Coming in v0.4',
              dimmed: true,
              onTap: null,
            ),
            const SizedBox(height: 12),
            _OptionCard(
              index: 2,
              selectedIndex: _selectedOption,
              icon: Icons.usb,
              title: 'USB TNC',
              subtitle: 'Connect via USB serial cable',
              dimmed:
                  kIsWeb ||
                  !(Platform.isLinux || Platform.isMacOS || Platform.isWindows),
              onTap:
                  (!kIsWeb &&
                      (Platform.isLinux ||
                          Platform.isMacOS ||
                          Platform.isWindows))
                  ? () => setState(() => _selectedOption = 2)
                  : null,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => widget.onStartListening(_selectedOption),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.surfaceLight,
                ),
                child: const Text('Start Listening'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.index,
    required this.selectedIndex,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.dimmed,
    required this.onTap,
  });

  final int index;
  final int selectedIndex;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool dimmed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSelected = index == selectedIndex;
    final borderColor = isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant;

    return Opacity(
      opacity: dimmed ? 0.45 : 1.0,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: borderColor, width: isSelected ? 2 : 1),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 32,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check_circle, color: theme.colorScheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
