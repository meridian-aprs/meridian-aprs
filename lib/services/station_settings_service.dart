/// Persistent My Station settings.
///
/// Owns all user-configurable identity fields (callsign, SSID, symbol,
/// comment, passcode, licensed status) that are consumed by
/// [BeaconingService] and [MessageService].
/// Persists changes immediately to [SharedPreferences] on every setter call —
/// there is no Save button.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether to use live GPS or a manually entered position for beaconing.
enum LocationSource { gps, manual }

class StationSettingsService extends ChangeNotifier {
  StationSettingsService(this._prefs)
    : _callsign = _prefs.getString(_keyCallsign) ?? '',
      _ssid = _prefs.getInt(_keySsid) ?? 0,
      _symbolTable = _prefs.getString(_keySymbolTable) ?? '/',
      _symbolCode = _prefs.getString(_keySymbolCode) ?? '>',
      _comment = _prefs.getString(_keyComment) ?? '',
      _manualLat = _prefs.getDouble(_keyManualLat),
      _manualLon = _prefs.getDouble(_keyManualLon),
      _locationSource =
          LocationSource.values.elementAtOrNull(
            _prefs.getInt(_keyLocationSource) ?? 0,
          ) ??
          LocationSource.gps,
      _isLicensed = _prefs.getBool(_keyIsLicensed) ?? false,
      _passcode = _prefs.getString(_keyPasscode) ?? '';

  final SharedPreferences _prefs;

  // SharedPreferences keys — reuse existing keys for callsign/SSID so that
  // values entered during onboarding are reflected here automatically.
  static const _keyCallsign = 'user_callsign';
  static const _keySsid = 'user_ssid';
  static const _keySymbolTable = 'user_symbol_table';
  static const _keySymbolCode = 'user_symbol_code';
  static const _keyComment = 'user_comment';
  static const _keyManualLat = 'user_manual_lat';
  static const _keyManualLon = 'user_manual_lon';
  static const _keyLocationSource = 'user_location_source';
  static const _keyIsLicensed = 'user_is_licensed';
  static const _keyPasscode = 'user_passcode';

  String _callsign;
  int _ssid;
  String _symbolTable;
  String _symbolCode;
  String _comment;
  double? _manualLat;
  double? _manualLon;
  LocationSource _locationSource;
  bool _isLicensed;
  String _passcode;

  String get callsign => _callsign;
  int get ssid => _ssid;
  String get symbolTable => _symbolTable;
  String get symbolCode => _symbolCode;
  String get comment => _comment;
  bool get isLicensed => _isLicensed;

  // plaintext stopgap; v0.13 migrates to secure storage
  String get passcode => _passcode;

  /// Whether to obtain position from live GPS or from [manualLat]/[manualLon].
  LocationSource get locationSource => _locationSource;

  /// Manually entered position. Null if not set.
  double? get manualLat => _manualLat;
  double? get manualLon => _manualLon;
  bool get hasManualPosition => _manualLat != null && _manualLon != null;

  /// Full AX.25 address string, e.g. `W1AW-9` (or `W1AW` when SSID is 0).
  String get fullAddress => _ssid == 0
      ? _callsign.toUpperCase()
      : '${_callsign.toUpperCase()}-$_ssid';

  Future<void> setCallsign(String value) async {
    final v = value.trim().toUpperCase();
    if (v == _callsign) return;
    _callsign = v;
    await _prefs.setString(_keyCallsign, v);
    notifyListeners();
  }

  Future<void> setSsid(int value) async {
    final v = value.clamp(0, 15);
    if (v == _ssid) return;
    _ssid = v;
    await _prefs.setInt(_keySsid, v);
    notifyListeners();
  }

  Future<void> setSymbol(String table, String code) async {
    if (table == _symbolTable && code == _symbolCode) return;
    _symbolTable = table;
    _symbolCode = code;
    await _prefs.setString(_keySymbolTable, table);
    await _prefs.setString(_keySymbolCode, code);
    notifyListeners();
  }

  Future<void> setComment(String value) async {
    // Enforce 36-character limit (safe margin within APRS spec).
    final v = value.length > 36 ? value.substring(0, 36) : value;
    if (v == _comment) return;
    _comment = v;
    await _prefs.setString(_keyComment, v);
    notifyListeners();
  }

  // TODO(license-transition): "I got my license" flow in Settings (FUTURE_FEATURES.md)
  Future<void> setIsLicensed(bool value) async {
    if (value == _isLicensed) return;
    _isLicensed = value;
    await _prefs.setBool(_keyIsLicensed, value);
    notifyListeners();
  }

  Future<void> setPasscode(String value) async {
    if (value == _passcode) return;
    _passcode = value;
    await _prefs.setString(_keyPasscode, value);
    notifyListeners();
  }

  Future<void> setLocationSource(LocationSource source) async {
    if (source == _locationSource) return;
    _locationSource = source;
    await _prefs.setInt(_keyLocationSource, source.index);
    notifyListeners();
  }

  Future<void> setManualPosition(double lat, double lon) async {
    _manualLat = lat;
    _manualLon = lon;
    await _prefs.setDouble(_keyManualLat, lat);
    await _prefs.setDouble(_keyManualLon, lon);
    notifyListeners();
  }

  Future<void> clearManualPosition() async {
    _manualLat = null;
    _manualLon = null;
    await _prefs.remove(_keyManualLat);
    await _prefs.remove(_keyManualLon);
    notifyListeners();
  }
}
