import 'package:latlong2/latlong.dart';

/// A single timestamped position snapshot for a station's movement track.
class TimestampedPosition {
  final DateTime timestamp;
  final LatLng position;
  const TimestampedPosition(this.timestamp, this.position);
}

/// Broad category used for the map type filter and cluster ring colouring.
///
/// Classification is based on APRS symbol codes ([classifyStationType]) for
/// position/Mic-E packets, and set to [object] for APRS object/item packets
/// regardless of their symbol.
enum StationType { weather, mobile, fixed, object, other }

/// Whether this station can receive APRS messages.
///
/// Derived from the position packet's data type indicator (DTI):
/// - `=` / `@` → [supported]
/// - `!` / `/` → [unsupported]
/// - Mic-E packets default to [supported] (Mic-E is overwhelmingly used by
///   messaging-capable mobile trackers; the spec doesn't expose a per-packet
///   flag).
/// - Object, Item, Weather, and stations with no position seen yet are
///   [unknown].
enum MessageCapability { supported, unsupported, unknown }

/// Derive a [StationType] from the station's APRS symbol table and code.
///
/// Objects and items must be classified by the caller as [StationType.object]
/// since their symbol alone does not distinguish them from fixed stations.
StationType classifyStationType(String symbolTable, String symbolCode) {
  // Weather stations — primary `_` or alternate-table `W`.
  if (symbolCode == '_') return StationType.weather;
  if (symbolTable == r'\' && symbolCode == 'W') return StationType.weather;

  // Mobile — vehicles, aircraft, watercraft (primary table only).
  const mobilePrimary = {
    '>', // car
    'j', // Jeep
    'k', // truck
    'u', // bus
    'v', // ATV / 4WD
    '^', // aircraft
    "'", // small aircraft
    'X', // helicopter
    's', // ship / power boat
    'Y', // yacht / sail boat
    'b', // bicycle
    'S', // motor boat
    'a', // ambulance
    'f', // fire truck
    'g', // balloon
    'O', // hot air balloon
  };
  if (symbolTable == '/' && mobilePrimary.contains(symbolCode)) {
    return StationType.mobile;
  }

  return StationType.fixed;
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

  /// Station category used for the map type filter and cluster ring.
  final StationType type;

  /// Whether this station can receive APRS messages.
  final MessageCapability messageCapability;

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
    this.type = StationType.fixed,
    this.messageCapability = MessageCapability.unknown,
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
    StationType? type,
    MessageCapability? messageCapability,
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
      type: type ?? this.type,
      messageCapability: messageCapability ?? this.messageCapability,
    );
  }

  /// Backward-compat alias for [lastHeard].
  DateTime get timestamp => lastHeard;
}
