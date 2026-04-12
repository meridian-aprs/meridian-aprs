import 'package:latlong2/latlong.dart';

/// A single timestamped position snapshot for a station's movement track.
class TimestampedPosition {
  final DateTime timestamp;
  final LatLng position;
  const TimestampedPosition(this.timestamp, this.position);
}

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

  /// Ordered position history for this station (oldest first), capped at 500
  /// entries. The current position ([lat]/[lon]) is NOT included in this list —
  /// it is the position of the most-recent packet, while this list holds prior
  /// positions to render a movement track.
  final List<TimestampedPosition> positionHistory;

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
    this.positionHistory = const [],
  });

  Station copyWith({
    String? callsign,
    double? lat,
    double? lon,
    String? rawPacket,
    DateTime? lastHeard,
    String? symbolTable,
    String? symbolCode,
    String? comment,
    String? device,
    List<TimestampedPosition>? positionHistory,
  }) {
    return Station(
      callsign: callsign ?? this.callsign,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      rawPacket: rawPacket ?? this.rawPacket,
      lastHeard: lastHeard ?? this.lastHeard,
      symbolTable: symbolTable ?? this.symbolTable,
      symbolCode: symbolCode ?? this.symbolCode,
      comment: comment ?? this.comment,
      device: device ?? this.device,
      positionHistory: positionHistory ?? this.positionHistory,
    );
  }

  /// Backward-compat alias for [lastHeard].
  DateTime get timestamp => lastHeard;
}
