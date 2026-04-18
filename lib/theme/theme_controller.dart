import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'meridian_colors.dart';

/// Manages the app-level [ThemeMode], seed [Color], and dynamic color
/// preference, persisting all three across launches via [SharedPreferences].
///
/// Replaces [ThemeProvider] from the pre-three-tier theme system.
///
/// Defaults on first launch:
/// - [themeMode]: [ThemeMode.system] (follows OS setting)
/// - [seedColor]: [MeridianColors.brandSeed] (Meridian Purple)
/// - [useDynamicColor]: true (use wallpaper-derived color when available)
///
/// Usage:
/// ```dart
/// final controller = context.watch<ThemeController>();
/// // In MaterialApp:
/// themeMode: controller.themeMode,
/// ```
class ThemeController extends ChangeNotifier {
  ThemeController._(this._themeMode, this._seedColor, this._useDynamicColor);

  ThemeMode _themeMode;
  Color _seedColor;
  bool _useDynamicColor;

  /// True once [reportDynamicColorAvailable] has been called by the app root.
  /// Not persisted — this is a device capability, detected at runtime.
  bool _dynamicColorAvailable = false;

  /// The currently active [ThemeMode].
  ThemeMode get themeMode => _themeMode;

  /// The user-selected seed color. Used as the active color when
  /// [useDynamicColor] is false, or as fallback when dynamic color is
  /// unavailable (Android < 12, desktop, iOS).
  Color get seedColor => _seedColor;

  /// Whether to use the wallpaper-derived dynamic color scheme (Android 12+).
  /// When false, [seedColor] is used instead.
  bool get useDynamicColor => _useDynamicColor;

  /// Whether this device supports dynamic color (Android 12+).
  /// Set once by [reportDynamicColorAvailable] when [DynamicColorBuilder]
  /// provides non-null schemes. Not persisted.
  bool get dynamicColorAvailable => _dynamicColorAvailable;

  // SharedPreferences keys.
  static const _themeModeKey = 'theme_mode'; // int: 0=system 1=light 2=dark
  static const _seedColorKey = 'seed_color'; // int: Color.toARGB32()
  static const _useDynamicColorKey = 'use_dynamic_color'; // bool

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
    final useDynamic = prefs.getBool(_useDynamicColorKey) ?? true;
    final mode = _modeFromInt(modeInt);
    final seed = seedInt != null ? Color(seedInt) : MeridianColors.brandSeed;
    return ThemeController._(mode, seed, useDynamic);
  }

  /// Called by [DynamicColorBuilder] when the device provides non-null dynamic
  /// schemes. Safe to call from within a build method — does not notify
  /// listeners, as the value is stable for the app lifetime and all consumers
  /// are built after this is first set.
  void reportDynamicColorAvailable() {
    _dynamicColorAvailable = true;
  }

  /// Update the active [ThemeMode] and persist the preference.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey, _modeToInt(mode));
  }

  /// Switch to the wallpaper-derived dynamic color scheme (Android 12+).
  Future<void> setUseDynamicColor() async {
    if (_useDynamicColor) return;
    _useDynamicColor = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useDynamicColorKey, true);
  }

  /// Switch to the manual [seedColor] and persist the preference.
  /// Automatically disables dynamic color so the seed takes effect.
  Future<void> setSeedColor(Color color) async {
    final colorChanged = _seedColor != color;
    final dynamicChanged = _useDynamicColor;
    if (!colorChanged && !dynamicChanged) return;
    _seedColor = color;
    _useDynamicColor = false;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setInt(_seedColorKey, color.toARGB32()),
      prefs.setBool(_useDynamicColorKey, false),
    ]);
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
