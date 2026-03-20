/// AX.25 frame model.
///
/// Full byte-level decoding (from KISS frames) is deferred to v0.3 TNC work.
/// This file establishes the canonical data model used across the transport
/// and packet core layers.
library;

/// AX.25 address field: callsign (up to 6 chars) + SSID (0–15).
class Ax25Address {
  const Ax25Address({
    required this.callsign,
    required this.ssid,
    this.hBit = false,
  });

  final String callsign;
  final int ssid;

  /// Whether the H-bit (has-been-repeated) is set for a digipeater entry.
  final bool hBit;

  @override
  String toString() => ssid == 0 ? callsign : '$callsign-$ssid';
}

/// Parsed AX.25 frame.
///
/// Decoding from raw bytes is not yet implemented (v0.3). This class acts as
/// the canonical data model for a decoded AX.25 frame so that the transport
/// layer (KISS/TNC) and packet core can share a common type.
class Ax25Frame {
  const Ax25Frame({
    required this.destination,
    required this.source,
    required this.digipeaters,
    required this.control,
    required this.pid,
    required this.info,
  });

  final Ax25Address destination;
  final Ax25Address source;

  /// Digipeater path (may be empty).
  final List<Ax25Address> digipeaters;

  /// Control field byte (UI frame = 0x03).
  final int control;

  /// Protocol ID byte (no layer 3 = 0xF0).
  final int pid;

  /// Information field — the APRS payload bytes.
  final List<int> info;

  /// Convenience: the digipeater path as a comma-separated string.
  String get pathString => digipeaters.join(',');
}
