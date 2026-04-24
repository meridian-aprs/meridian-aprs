/// Classification tag applied to every ingested APRS message packet by
/// [AddresseeMatcher.classifyWithPrecedence]. See ADR-055.
enum MessageCategory {
  /// Addressed to the operator's own callsign (any SSID).
  direct,

  /// Matched an enabled [GroupSubscription].
  group,

  /// Bulletin (BLN0–BLN9 or BLNxNAME). Stored in the `Bulletin` table, not in
  /// [MessageEntry] — carried here for completeness only.
  bulletin,
}
