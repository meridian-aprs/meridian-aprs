/// Persistent My Station settings.
///
/// Owns all user-configurable identity fields (callsign, SSID, symbol,
/// comment, passcode, licensed status) that are consumed by
/// [BeaconingService] and [MessageService].
/// Persists changes immediately to [SharedPreferences] on every setter call —
/// there is no Save button.
///
/// The APRS-IS passcode is the one exception: it is persisted to
/// [SecureCredentialStore] (platform keychain / keystore) rather than
/// SharedPreferences. Call [load] after construction and before the first
/// read of [passcode] to prime the in-memory cache from the secure store.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/connection/connection_credentials.dart';
import '../core/credentials/credential_key.dart';
import '../core/credentials/secure_credential_store.dart';

/// Whether to use live GPS or a manually entered position for beaconing.
enum LocationSource { gps, manual }

class StationSettingsService extends ChangeNotifier {
  StationSettingsService(this._prefs, {required SecureCredentialStore store})
    : _store = store,
      _callsign = _prefs.getString(_keyCallsign) ?? '',
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
      _passcode = '';

  final SharedPreferences _prefs;
  final SecureCredentialStore _store;

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

  /// APRS-IS passcode, primed from [SecureCredentialStore] by [load].
  ///
  /// Returns an empty string before [load] completes (or if no passcode is
  /// stored). Call sites that need a fresh value should await [load] at
  /// startup — the secure store read is asynchronous but the getter itself
  /// stays synchronous for UI consumption.
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

  /// Current credentials snapshot, suitable for pushing into
  /// [AprsIsConnection.setCredentials].
  ConnectionCredentials get credentials => ConnectionCredentials(
    callsign: _callsign,
    ssid: _ssid,
    passcode: _passcode,
    isLicensed: _isLicensed,
  );

  /// Prime async-backed fields (currently just [passcode]) from their
  /// underlying stores. Call once at startup — and from onboarding — before
  /// relying on the synchronous getter.
  ///
  /// Swallows [CredentialStoreException] silently: a failing secure store
  /// leaves [passcode] empty, which the APRS-IS layer treats as the
  /// unlicensed `-1` fallback. Errors are visible in debug output via the
  /// store's own logging.
  Future<void> load() async {
    String? stored;
    try {
      stored = await _store.read(CredentialKey.aprsIsPasscode);
    } catch (_) {
      // SecureCredentialStore already logs platform errors; callers treat
      // a missing passcode as receive-only (ADR-045).
      stored = null;
    }
    final next = stored ?? '';
    if (next == _passcode) return;
    _passcode = next;
    notifyListeners();
  }

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
    if (value.isEmpty) {
      await _store.delete(CredentialKey.aprsIsPasscode);
    } else {
      await _store.write(CredentialKey.aprsIsPasscode, value);
    }
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
