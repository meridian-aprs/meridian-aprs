class Station {
  final String callsign;
  final double lat;
  final double lon;
  final String rawPacket;
  final DateTime timestamp;

  const Station({
    required this.callsign,
    required this.lat,
    required this.lon,
    required this.rawPacket,
    required this.timestamp,
  });
}
