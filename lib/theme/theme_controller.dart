import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'meridian_colors.dart';

/// Manages the app-level [ThemeMode] and seed [Color], persisting both across
/// launches via [SharedPreferences].
///
/// Replaces [ThemeProvider] from the pre-three-tier theme system.
///
/// Defaults on first launch:
/// - [themeMode]: [ThemeMode.system] (follows OS setting)
/// - [seedColor]: [MeridianColors.primary] (Meridian Blue)
///
/// Usage:
/// ```dart
/// final controller = context.watch<ThemeController>();
/// // In MaterialApp:
/// themeMode: controller.themeMode,
/// ```
class ThemeController extends ChangeNotifier {
  ThemeController._(this._themeMode, this._seedColor);

  ThemeMode _themeMode;
  Color _seedColor;

  /// The currently active [ThemeMode].
  ThemeMode get themeMode => _themeMode;

  /// The user-selected seed color used as the dynamic color fallback on
  /// Android < 12, and as the fixed seed on desktop and iOS.
  Color get seedColor => _seedColor;

  // SharedPreferences keys.
  static const _themeModeKey =
      'theme_mode'; // stored as int: 0=system 1=light 2=dark
  static const _seedColorKey = 'seed_color'; // stored as int: Color.value

  // NOTE: The previous ThemeProvider stored theme_mode as a string under the
  // same key. On first launch after this migration, prefs.getInt('theme_mode')
  // returns null (type mismatch). The fallback to ThemeMode.system is correct.

  /// Loads persisted preferences and returns a ready [ThemeController].
  static Future<ThemeController> create() async {
    final prefs = await SharedPreferences.getInstance();

    // getInt throws a type cast exception if the stored value is a String.
    // The previous ThemeProvider stored theme_mode as a string ("system",
    // "light", "dark") under the same key. Remove it so future reads work.
    int? modeInt;
    try {
      modeInt = prefs.getInt(_themeModeKey);
    } catch (_) {
      await prefs.remove(_themeModeKey);
    }

    final seedInt = prefs.getInt(_seedColorKey);
    final mode = _modeFromInt(modeInt);
    final seed = seedInt != null ? Color(seedInt) : MeridianColors.primary;
    return ThemeController._(mode, seed);
  }

  /// Update the active [ThemeMode] and persist the preference.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey, _modeToInt(mode));
  }

  /// Update the seed color and persist the preference.
  ///
  /// On Android 12+ the seed is only used when dynamic color is unavailable.
  /// On desktop and iOS the seed is always used.
  Future<void> setSeedColor(Color color) async {
    if (_seedColor == color) return;
    _seedColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_seedColorKey, color.toARGB32());
  }

  static ThemeMode _modeFromInt(int? raw) {
    switch (raw) {
      case 1:
        return ThemeMode.light;
      case 2:
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static int _modeToInt(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 1;
      case ThemeMode.dark:
        return 2;
      case ThemeMode.system:
        return 0;
    }
  }
}
