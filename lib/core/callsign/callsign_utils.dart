library;

/// Returns the base callsign with SSID stripped (everything before the last dash).
///
/// Handles numeric SSIDs (0–15), D-STAR letter SSIDs (A–Z), and no-SSID forms.
/// Input is trimmed and uppercased.
///
/// Examples:
///   'KM4TJO'    → 'KM4TJO'
///   'km4tjo-0'  → 'KM4TJO'
///   'KM4TJO-9'  → 'KM4TJO'
///   'KM4TJO-15' → 'KM4TJO'
///   'KM4TJO-A'  → 'KM4TJO'
String stripSsid(String callsign) {
  final upper = callsign.trim().toUpperCase();
  final dashIdx = upper.lastIndexOf('-');
  return dashIdx == -1 ? upper : upper.substring(0, dashIdx);
}

/// Normalizes a callsign so that '-0' and no suffix are equivalent.
///
/// Per APRS spec, SSID -0 is the same station as no SSID.
/// All other SSIDs are returned unchanged (uppercased, trimmed).
///
/// Examples:
///   'KM4TJO-0' → 'KM4TJO'
///   'KM4TJO'   → 'KM4TJO'
///   'KM4TJO-9' → 'KM4TJO-9'
String normalizeCallsign(String callsign) {
  final upper = callsign.trim().toUpperCase();
  return upper.endsWith('-0') ? upper.substring(0, upper.length - 2) : upper;
}
