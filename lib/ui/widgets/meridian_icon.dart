import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Meridian APRS pin icon for in-app UI rendering.
///
/// Automatically adapts to light/dark theme:
/// - Light mode: brand040 purple (#4D1D8C)
/// - Dark mode: brand080 lighter purple (#C8B0E8), tuned for dark surfaces
///   (5.7:1 contrast vs neutral010 — passes WCAG AA)
///
/// NOT for launcher icons — the Android adaptive icon and iOS home screen
/// icon are managed by the OS, not this widget.
class MeridianIcon extends StatelessWidget {
  final double? size;

  const MeridianIcon({super.key, this.size});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = isDark
        ? 'assets/icons/meridian-icon-master-dark.svg'
        : 'assets/icons/meridian-icon-master.svg';
    return SvgPicture.asset(
      asset,
      height: size,
      width: size,
      semanticsLabel: 'Meridian APRS',
    );
  }
}
