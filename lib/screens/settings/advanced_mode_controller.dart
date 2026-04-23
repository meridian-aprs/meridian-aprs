import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdvancedModeController extends ChangeNotifier {
  AdvancedModeController._(this._enabled);

  bool _enabled;

  static const _key = 'advanced_user_mode_enabled';

  bool get isEnabled => _enabled;

  static Future<AdvancedModeController> create() async {
    final prefs = await SharedPreferences.getInstance();
    return AdvancedModeController._(prefs.getBool(_key) ?? false);
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}
