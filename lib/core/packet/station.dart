class Station {
  final String callsign;
  final double lat;
  final double lon;
  final String rawPacket;
  final DateTime lastHeard;
  final String symbolTable;
  final String symbolCode;
  final String comment;

  /// Human-readable device or software name (e.g. "APRSdroid", "Dire Wolf"),
  /// or null if not resolved.
  final String? device;

  const Station({
    required this.callsign,
    required this.lat,
    required this.lon,
    required this.rawPacket,
    required this.lastHeard,
    required this.symbolTable,
    required this.symbolCode,
    required this.comment,
    this.device,
  });

  /// Backward-compat alias for [lastHeard].
  DateTime get timestamp => lastHeard;
}
