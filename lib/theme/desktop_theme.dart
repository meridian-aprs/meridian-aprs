import 'package:flutter/material.dart';

import 'meridian_colors.dart';

/// Builds the desktop theme pair (light + dark) for Windows, macOS, and Linux.
///
/// Material 3 with a fixed [seedColor] — no dynamic color, no M3 Expressive
/// ThemeExtension (Android-only). Callers always pass [MeridianColors.primary].
({ThemeData light, ThemeData dark}) buildDesktopTheme({
  required Color seedColor,
}) {
  final lightScheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: Brightness.light,
  );
  final darkScheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: Brightness.dark,
  );
  return (
    light: ThemeData(useMaterial3: true, colorScheme: lightScheme),
    dark: ThemeData(useMaterial3: true, colorScheme: darkScheme),
  );
}
