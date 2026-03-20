import 'package:flutter/material.dart';

/// Meridian APRS design token colors.
///
/// All UI code must reference these constants (or derive from them via
/// Theme.of(context)) rather than hard-coding color values.
class AppColors {
  AppColors._();

  // Primary — Meridian Blue
  static const Color primaryLight = Color(0xFF2563EB);
  static const Color primaryDark = Color(0xFF3B82F6);

  // Primary variant
  static const Color primaryDarkLight = Color(0xFF1D4ED8);
  static const Color primaryDarkDark = Color(0xFF2563EB);

  // Semantic
  static const Color accent = Color(0xFF10B981); // Signal Green
  static const Color warning = Color(0xFFF59E0B); // Amber
  static const Color danger = Color(0xFFEF4444); // Red

  // Surface — light mode
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceVariantLight = Color(0xFFF8FAFC);

  // Surface — dark mode
  static const Color surfaceDark = Color(0xFF0F172A);
  static const Color surfaceVariantDark = Color(0xFF1E293B);

  // Text
  static const Color textLight = Color(0xFF0F172A);
  static const Color textDark = Color(0xFFF1F5F9);

  // Dark-theme primary container foreground
  static const Color onPrimaryContainerDark = Color(0xFFBFDBFE);
}

/// Provides the Material 3 [ThemeData] instances used throughout Meridian.
///
/// Use [AppTheme.lightTheme] and [AppTheme.darkTheme] in [MaterialApp].
/// All widget colors must be derived from [Theme.of(context)] — never
/// hard-code a color value.
class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primaryLight,
      brightness: Brightness.light,
      primary: AppColors.primaryLight,
      onPrimary: AppColors.surfaceLight,
      primaryContainer: AppColors.primaryLight.withAlpha(30),
      onPrimaryContainer: AppColors.primaryDarkLight,
      secondary: AppColors.accent,
      onSecondary: AppColors.surfaceLight,
      error: AppColors.danger,
      surface: AppColors.surfaceLight,
      onSurface: AppColors.textLight,
      surfaceContainerHighest: AppColors.surfaceVariantLight,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.surfaceLight,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surfaceLight,
        foregroundColor: AppColors.textLight,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.surfaceVariantLight,
        selectedIconTheme: IconThemeData(color: AppColors.primaryLight),
        selectedLabelTextStyle: TextStyle(
          color: AppColors.primaryLight,
          fontWeight: FontWeight.w600,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primaryLight,
        foregroundColor: AppColors.surfaceLight,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceLight,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primaryDark,
      brightness: Brightness.dark,
      primary: AppColors.primaryDark,
      onPrimary: AppColors.surfaceDark,
      primaryContainer: AppColors.primaryDark.withAlpha(40),
      onPrimaryContainer: AppColors.onPrimaryContainerDark,
      secondary: AppColors.accent,
      onSecondary: AppColors.surfaceDark,
      error: AppColors.danger,
      surface: AppColors.surfaceDark,
      onSurface: AppColors.textDark,
      surfaceContainerHighest: AppColors.surfaceVariantDark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.surfaceDark,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surfaceDark,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.surfaceVariantDark,
        selectedIconTheme: IconThemeData(color: AppColors.primaryDark),
        selectedLabelTextStyle: TextStyle(
          color: AppColors.primaryDark,
          fontWeight: FontWeight.w600,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primaryDark,
        foregroundColor: AppColors.textDark,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceVariantDark,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
