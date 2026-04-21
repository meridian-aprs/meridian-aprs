/// Station credentials consumed by connections that need to authenticate.
///
/// A plain value type that decouples [AprsIsConnection] (and other future
/// connections that might need credentials) from the service layer. Previously
/// [AprsIsConnection] imported [StationSettingsService] directly to read the
/// callsign / passcode / licensed state — a Core → Service layer violation.
///
/// The UI layer (`main.dart`, onboarding) builds this snapshot from
/// [StationSettingsService] and pushes it into the connection, so the
/// connection core never reaches upward.
///
/// Unlicensed users (ADR-045) still receive a connection with their real
/// callsign captured in this value; [AprsIsConnection] substitutes the
/// `N0CALL` / passcode `-1` receive-only form on connect when [isLicensed] is
/// false.
library;

import '../../config/app_version.dart';

class ConnectionCredentials {
  const ConnectionCredentials({
    required this.callsign,
    required this.ssid,
    required this.passcode,
    required this.isLicensed,
  });

  /// Amateur callsign without SSID suffix, uppercased. Empty when the user
  /// has not completed onboarding.
  final String callsign;

  /// APRS SSID in the range 0..15.
  final int ssid;

  /// APRS-IS passcode string. Empty if not yet entered — in that case
  /// [aprsIsLoginLine] falls back to the unlicensed `-1` passcode.
  final String passcode;

  /// Whether the user has declared themselves licensed. When false,
  /// connections that authenticate must force a receive-only login
  /// (see [AprsIsConnection]).
  final bool isLicensed;

  /// Full AX.25 address string, e.g. `W1AW-9` (or `W1AW` when SSID is 0).
  String get fullAddress {
    final cs = callsign.isEmpty ? 'NOCALL' : callsign;
    return ssid == 0 ? cs : '$cs-$ssid';
  }

  /// APRS-IS login line ending in `\r\n`, ready for
  /// [AprsIsTransport.updateCredentials] / the initial connect handshake.
  ///
  /// Always emits a valid login — if [passcode] is empty, the unlicensed
  /// `-1` passcode is used (receive-only mode, accepted by APRS-IS servers).
  /// [AprsIsConnection] will further override the entire line when
  /// [isLicensed] is false.
  String get aprsIsLoginLine {
    final effectivePasscode = passcode.isEmpty ? '-1' : passcode;
    return 'user $fullAddress pass $effectivePasscode '
        'vers meridian-aprs $kAppVersion\r\n';
  }

  ConnectionCredentials copyWith({
    String? callsign,
    int? ssid,
    String? passcode,
    bool? isLicensed,
  }) => ConnectionCredentials(
    callsign: callsign ?? this.callsign,
    ssid: ssid ?? this.ssid,
    passcode: passcode ?? this.passcode,
    isLicensed: isLicensed ?? this.isLicensed,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectionCredentials &&
          other.callsign == callsign &&
          other.ssid == ssid &&
          other.passcode == passcode &&
          other.isLicensed == isLicensed;

  @override
  int get hashCode => Object.hash(callsign, ssid, passcode, isLicensed);

  @override
  String toString() =>
      'ConnectionCredentials(callsign: $callsign, ssid: $ssid, '
      'passcode: ${passcode.isEmpty ? '<empty>' : '<redacted>'}, '
      'isLicensed: $isLicensed)';
}
