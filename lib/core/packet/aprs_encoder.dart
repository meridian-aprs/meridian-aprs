/// APRS packet text encoder.
///
/// Produces APRS-IS formatted strings from structured data. Pure Dart — no
/// platform imports. Used by [BeaconingService] and [MessageService] to
/// construct outgoing packets before they are dispatched via [TxService].
library;

import 'aprs_identity.dart';

/// Encodes APRS packets as APRS-IS text lines.
///
/// All output includes `TCPIP*` in the path per the APRS-IS connecting spec.
/// This encoder produces APRS-IS–only output and must not be used to generate
/// frames transmitted over RF; use [Ax25Encoder] for RF paths.
class AprsEncoder {
  AprsEncoder._();

  static String get _dest => AprsIdentity.tocall;

  // -------------------------------------------------------------------------
  // Position
  // -------------------------------------------------------------------------

  /// Encodes an uncompressed APRS position packet.
  ///
  /// Returns a full APRS-IS line including the header, e.g.:
  /// `W1AW-9>APMDN0,TCPIP*:=4903.50N/07201.75W>Comment`
  ///
  /// [callsign] must be 3–7 uppercase alphanumeric characters.
  /// [ssid] 0–15; omitted from header when 0.
  /// [symbolTable] is `'/'` (primary) or `'\\'` (alternate).
  /// [symbolCode] is the single APRS symbol character.
  /// DTI is always `=` (messaging-capable, no timestamp) because Meridian
  /// always supports messaging.
  static String encodePosition({
    required String callsign,
    required int ssid,
    required double lat,
    required double lon,
    required String symbolTable,
    required String symbolCode,
    String comment = '',
  }) {
    assert(lat >= -90 && lat <= 90, 'lat must be in [-90, 90], got $lat');
    assert(lon >= -180 && lon <= 180, 'lon must be in [-180, 180], got $lon');
    final src = _formatAddress(callsign, ssid);
    const dti = '=';
    final latStr = _encodeLat(lat);
    final lonStr = _encodeLon(lon);
    return '$src>$_dest,TCPIP*:$dti$latStr$symbolTable$lonStr$symbolCode$comment';
  }

  // -------------------------------------------------------------------------
  // Message
  // -------------------------------------------------------------------------

  /// Encodes an APRS message packet (APRS spec §14).
  ///
  /// Returns a full APRS-IS line, e.g.:
  /// `W1AW-9>APMDN0,TCPIP*::WB4APR   :Hello there{001`
  ///
  /// [toCallsign] is padded/truncated to 9 characters per spec.
  /// [messageId] is appended as `{id}` when non-null and non-empty.
  static String encodeMessage({
    required String fromCallsign,
    required int fromSsid,
    required String toCallsign,
    required String text,
    String? messageId,
  }) {
    final header = _header(fromCallsign, fromSsid);
    final addressee = _padAddressee(toCallsign);
    final idSuffix = (messageId != null && messageId.isNotEmpty)
        ? '{$messageId'
        : '';
    return '$header:$addressee:$text$idSuffix';
  }

  /// Encodes an APRS ACK packet.
  ///
  /// Returns a full APRS-IS line, e.g.:
  /// `W1AW-9>APMDN0,TCPIP*::WB4APR   :ack001`
  static String encodeAck({
    required String fromCallsign,
    required int fromSsid,
    required String toCallsign,
    required String messageId,
  }) {
    final header = _header(fromCallsign, fromSsid);
    final addressee = _padAddressee(toCallsign);
    return '$header:$addressee:ack$messageId';
  }

  /// Encodes an APRS REJ packet.
  static String encodeRej({
    required String fromCallsign,
    required int fromSsid,
    required String toCallsign,
    required String messageId,
  }) {
    final header = _header(fromCallsign, fromSsid);
    final addressee = _padAddressee(toCallsign);
    return '$header:$addressee:rej$messageId';
  }

  // -------------------------------------------------------------------------
  // Bulletin (v0.17, ADR-057)
  // -------------------------------------------------------------------------

  /// Encodes an APRS bulletin. Bulletins use the same wire format as direct
  /// messages but are never ACKed — no `{id}` suffix.
  ///
  /// Returns a full APRS-IS line, e.g.:
  /// `W1ABC-7>APMDN0,TCPIP*::BLN0     :Severe wx alert`
  ///
  /// [addressee] is the bulletin addressee (`BLN0`..`BLN9` for general;
  /// `BLNxNAME` for named groups where `x` is `0`–`9` or `A`–`Z`). Padded
  /// to 9 characters per APRS spec §14.
  static String encodeBulletin({
    required String fromCallsign,
    required int fromSsid,
    required String addressee,
    required String body,
  }) {
    final header = _header(fromCallsign, fromSsid);
    final padded = _padAddressee(addressee);
    return '$header:$padded:$body';
  }

  // -------------------------------------------------------------------------
  // Group message (v0.17, ADR-056)
  // -------------------------------------------------------------------------

  /// Encodes an APRS group message (e.g. `CQ`, `QST`, `CLUB`). Group
  /// messages share the direct-message wire format but omit the message-ID
  /// suffix — per ADR-055 they are never ACKed, so the ID-suffix machinery
  /// is intentionally absent.
  ///
  /// Returns a full APRS-IS line, e.g.:
  /// `W1ABC-7>APMDN0,TCPIP*::CQ       :CQ CQ — anyone on freq?`
  static String encodeGroupMessage({
    required String fromCallsign,
    required int fromSsid,
    required String groupName,
    required String body,
  }) {
    final header = _header(fromCallsign, fromSsid);
    final addressee = _padAddressee(groupName);
    return '$header:$addressee:$body';
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// Returns the APRS-IS packet header for [callsign]/[ssid], including the
  /// `TCPIP*` path that APRS-IS servers require for internet-originated packets.
  ///
  /// Example: `W1AW-9>APMDN0,TCPIP*:`
  static String _header(String callsign, int ssid) {
    final src = _formatAddress(callsign, ssid);
    return '$src>$_dest,TCPIP*:';
  }

  static String _formatAddress(String callsign, int ssid) =>
      ssid == 0 ? callsign.toUpperCase() : '${callsign.toUpperCase()}-$ssid';

  /// Pads or truncates [callsign] to exactly 9 characters (APRS spec §14).
  static String _padAddressee(String callsign) =>
      callsign.toUpperCase().padRight(9).substring(0, 9);

  /// Encodes latitude to `DDMM.HHN` or `DDMM.HHS` format.
  static String _encodeLat(double lat) {
    final hemi = lat >= 0 ? 'N' : 'S';
    final abs = lat.abs();
    final deg = abs.truncate();
    final min = (abs - deg) * 60.0;
    return '${deg.toString().padLeft(2, '0')}${_formatMinutes(min)}$hemi';
  }

  /// Encodes longitude to `DDDMM.HHE` or `DDDMM.HHW` format.
  static String _encodeLon(double lon) {
    final hemi = lon >= 0 ? 'E' : 'W';
    final abs = lon.abs();
    final deg = abs.truncate();
    final min = (abs - deg) * 60.0;
    return '${deg.toString().padLeft(3, '0')}${_formatMinutes(min)}$hemi';
  }

  /// Formats decimal minutes as `MM.HH` (2 integer digits, 2 decimal digits).
  static String _formatMinutes(double min) {
    final intPart = min.truncate().toString().padLeft(2, '0');
    final fracPart = ((min - min.truncate()) * 100)
        .truncate()
        .toString()
        .padLeft(2, '0');
    return '$intPart.$fracPart';
  }
}
