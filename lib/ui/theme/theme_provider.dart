import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the app-level [ThemeMode] and persists the user's preference
/// across launches via [SharedPreferences].
///
/// Default on first launch: [ThemeMode.system] (follows OS setting).
///
/// Usage:
/// ```dart
/// // In MaterialApp:
/// final provider = context.watch<ThemeProvider>();
/// MaterialApp(
///   themeMode: provider.themeMode,
///   theme: AppTheme.lightTheme,
///   darkTheme: AppTheme.darkTheme,
/// );
/// ```
class ThemeProvider extends ChangeNotifier {
  ThemeProvider._(this._themeMode);

  ThemeMode _themeMode;

  /// The currently active [ThemeMode].
  ThemeMode get themeMode => _themeMode;

  static const _prefKey = 'theme_mode';

  /// Factory constructor that loads the persisted preference from
  /// [SharedPreferences] before returning the provider instance.
  static Future<ThemeProvider> create() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    final mode = _modeFromString(raw);
    return ThemeProvider._(mode);
  }

  /// Update the active theme and persist the preference.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, _modeToString(mode));
  }

  static ThemeMode _modeFromString(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _modeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
