class Station {
  final String callsign;
  final double lat;
  final double lon;
  final String rawPacket;
  final DateTime lastHeard;
  final String symbolTable;
  final String symbolCode;
  final String comment;

  const Station({
    required this.callsign,
    required this.lat,
    required this.lon,
    required this.rawPacket,
    required this.lastHeard,
    required this.symbolTable,
    required this.symbolCode,
    required this.comment,
  });

  /// Backward-compat alias for [lastHeard].
  DateTime get timestamp => lastHeard;
}
