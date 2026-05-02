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

import '../core/callsign/operator_identity.dart';
import '../core/connection/aprs_is_filter_config.dart';
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
            _prefs.getInt(_keyLocationSource) ?? _defaultLocationSourceIndex(),
          ) ??
          LocationSource.gps,
      _isLicensed = _prefs.getBool(_keyIsLicensed) ?? false,
      _passcode = '',
      _aprsIsFilter = _loadAprsIsFilter(_prefs);

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

  // APRS-IS filter configuration keys (v0.13).
  static const _keyAprsIsFilterPreset = 'aprs_is_filter_preset';
  static const _keyAprsIsFilterPadPct = 'aprs_is_filter_pad_pct';
  static const _keyAprsIsFilterMinRadiusKm = 'aprs_is_filter_min_radius_km';

  // Remembered Custom-preset tuple so switching Custom → Regional → Custom
  // restores the user's last Custom values rather than Regional's.
  static const _keyAprsIsFilterCustomPadPct = 'aprs_is_filter_custom_pad_pct';
  static const _keyAprsIsFilterCustomMinRadiusKm =
      'aprs_is_filter_custom_min_radius_km';

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
  AprsIsFilterConfig _aprsIsFilter;

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

  /// Identity snapshot for the addressee matcher (ADR-055).
  ///
  /// Composes the callsign + SSID fields into the form the matcher needs. Does
  /// not include passcode or licensing state — those belong to
  /// [ConnectionCredentials] only.
  OperatorIdentity get operatorIdentity =>
      OperatorIdentity(callsign: _callsign, ssid: _ssid);

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

  // ---------------------------------------------------------------------------
  // APRS-IS server-side filter configuration
  // ---------------------------------------------------------------------------

  /// Active APRS-IS server-side filter configuration.
  ///
  /// Consumed by [AprsIsConnection.updateFilter] to compose the `#filter a/`
  /// line pushed to the server on every viewport change. Persists the full
  /// tuple so the user's Custom values survive even when they switch to a
  /// named preset and back.
  AprsIsFilterConfig get aprsIsFilter => _aprsIsFilter;

  Future<void> setAprsIsFilter(AprsIsFilterConfig config) async {
    if (config == _aprsIsFilter) return;
    _aprsIsFilter = config;
    await _prefs.setString(_keyAprsIsFilterPreset, config.preset.name);
    await _prefs.setDouble(_keyAprsIsFilterPadPct, config.padPct);
    await _prefs.setDouble(_keyAprsIsFilterMinRadiusKm, config.minRadiusKm);
    notifyListeners();
  }

  /// Remembered Custom-preset tuple. Returns null if the user has never
  /// tweaked an advanced value (i.e. has only ever selected named presets).
  ///
  /// The UI uses this to restore the user's last Custom values when they
  /// re-select the Custom segment after hopping through a named preset —
  /// without this the [_selectPreset] path would snap Custom to whatever
  /// tuple the current named preset happens to carry.
  AprsIsFilterConfig? get aprsIsFilterCustom {
    final padPct = _prefs.getDouble(_keyAprsIsFilterCustomPadPct);
    final minRadiusKm = _prefs.getDouble(_keyAprsIsFilterCustomMinRadiusKm);
    if (padPct == null || minRadiusKm == null) return null;
    return AprsIsFilterConfig(
      preset: AprsIsFilterPreset.custom,
      padPct: padPct,
      minRadiusKm: minRadiusKm,
    );
  }

  /// Persist the user's Custom tuple. The [preset] field of [config] is
  /// ignored — this slot is always treated as the Custom bucket.
  Future<void> setAprsIsFilterCustom(AprsIsFilterConfig config) async {
    await _prefs.setDouble(_keyAprsIsFilterCustomPadPct, config.padPct);
    await _prefs.setDouble(
      _keyAprsIsFilterCustomMinRadiusKm,
      config.minRadiusKm,
    );
    // No notifyListeners — the active filter state is [aprsIsFilter], not
    // this remembered slot. Callers typically update both in one operation.
  }

  /// Default `LocationSource` index for first-run installs.
  ///
  /// Linux desktop has no `geolocator` plugin implementation, so defaulting
  /// to GPS would produce silent beacon failures with no manual coordinates
  /// to fall back on. Default to manual there. Every other platform keeps
  /// GPS as the first-run default.
  static int _defaultLocationSourceIndex() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      return LocationSource.manual.index;
    }
    return LocationSource.gps.index;
  }

  /// Rehydrate the persisted [AprsIsFilterConfig], falling back to
  /// [AprsIsFilterConfig.defaultConfig] when prefs are empty.
  static AprsIsFilterConfig _loadAprsIsFilter(SharedPreferences prefs) {
    final presetName = prefs.getString(_keyAprsIsFilterPreset);
    if (presetName == null) return AprsIsFilterConfig.defaultConfig;

    final preset = AprsIsFilterPreset.values.firstWhere(
      (p) => p.name == presetName,
      orElse: () => AprsIsFilterPreset.regional,
    );
    final defaults = AprsIsFilterConfig.defaultConfig;
    final padPct = prefs.getDouble(_keyAprsIsFilterPadPct) ?? defaults.padPct;
    final minRadiusKm =
        prefs.getDouble(_keyAprsIsFilterMinRadiusKm) ?? defaults.minRadiusKm;
    return AprsIsFilterConfig(
      preset: preset,
      padPct: padPct,
      minRadiusKm: minRadiusKm,
    );
  }
}
