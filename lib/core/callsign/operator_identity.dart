/// Immutable snapshot of the operator's identity for addressee classification.
///
/// Kept separate from `ConnectionCredentials` because the matcher does not need
/// the passcode or licensed flag — only the callsign shape. Build via
/// [StationSettingsService.operatorIdentity].
library;

import 'callsign_utils.dart';

class OperatorIdentity {
  OperatorIdentity({required String callsign, required this.ssid})
    : callsign = callsign.toUpperCase(),
      _fullAddressNormalized = normalizeCallsign(
        ssid == 0 ? callsign.toUpperCase() : '${callsign.toUpperCase()}-$ssid',
      ),
      _baseCallsign = stripSsid(callsign.toUpperCase());

  /// The bare callsign (no SSID), uppercased.
  final String callsign;

  /// Numeric SSID (0–15); letter SSIDs are not representable here because the
  /// operator's own SSID is stored as an integer in settings.
  final int ssid;

  final String _fullAddressNormalized;
  final String _baseCallsign;

  /// True when [callsign] is empty — e.g., before onboarding completes.
  bool get isEmpty => callsign.isEmpty;

  /// Full AX.25-style address with `-0` stripped (matches APRS spec).
  String get fullAddressNormalized => _fullAddressNormalized;

  /// Base callsign without SSID.
  String get baseCallsign => _baseCallsign;

  /// True if [addressee] targets this operator's callsign in any SSID form
  /// (exact-match or cross-SSID per ADR-054).
  ///
  /// Returns false when the identity is empty (pre-onboarding) so messages
  /// don't classify as direct before the user has a callsign.
  bool matchesOwnCallsign(String addressee) {
    if (isEmpty) return false;
    final normalized = normalizeCallsign(addressee);
    if (normalized == _fullAddressNormalized) return true;
    return stripSsid(normalized) == _baseCallsign;
  }

  /// True when the match is exact (same SSID). Only exact matches get ACKed;
  /// cross-SSID matches are displayed but never ACKed (ADR-054).
  bool matchesExactly(String addressee) {
    if (isEmpty) return false;
    return normalizeCallsign(addressee) == _fullAddressNormalized;
  }

  @override
  bool operator ==(Object other) =>
      other is OperatorIdentity &&
      other.callsign == callsign &&
      other.ssid == ssid;

  @override
  int get hashCode => Object.hash(callsign, ssid);
}
