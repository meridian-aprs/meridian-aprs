/// Identifies which transport delivered this packet.
enum PacketSource { aprsIs, tnc }

/// Typed APRS packet model hierarchy.
///
/// Every decoded packet is one of the concrete subtypes below. Use pattern
/// matching (switch / is) to dispatch on packet type in UI or service code.
///
/// The sealed base [AprsPacket] carries the fields present in every packet:
/// the original raw APRS-IS line, the source callsign, the destination, the
/// digipeater path, and a UTC receive timestamp.
sealed class AprsPacket {
  /// Original APRS-IS line as received.
  final String rawLine;

  /// Source callsign, e.g. "W1AW-9".
  final String source;

  /// Destination field, e.g. "APRS" or a Mic-E encoded string.
  final String destination;

  /// Digipeater path, e.g. ["WIDE1-1", "WIDE2-1"].
  final List<String> path;

  /// UTC timestamp at which this packet was received / parsed.
  final DateTime receivedAt;

  /// Which transport delivered this packet.
  final PacketSource transportSource;

  const AprsPacket({
    required this.rawLine,
    required this.source,
    required this.destination,
    required this.path,
    required this.receivedAt,
    this.transportSource = PacketSource.aprsIs,
  });
}

// ---------------------------------------------------------------------------
// Position
// ---------------------------------------------------------------------------

/// An APRS position report (DTI: ! = / @).
///
/// [hasMessaging] is true when the DTI was `=` or `@` (indicates the station
/// supports APRS messaging).
class PositionPacket extends AprsPacket {
  final double lat;
  final double lon;
  final String symbolTable;
  final String symbolCode;
  final String comment;
  final double? altitude;
  final int? course;
  final double? speed;
  final bool hasMessaging;

  /// Timestamp encoded inside the APRS info field (not the receive time).
  final DateTime? timestamp;

  const PositionPacket({
    required super.rawLine,
    required super.source,
    required super.destination,
    required super.path,
    required super.receivedAt,
    super.transportSource,
    required this.lat,
    required this.lon,
    required this.symbolTable,
    required this.symbolCode,
    required this.comment,
    this.altitude,
    this.course,
    this.speed,
    required this.hasMessaging,
    this.timestamp,
  });
}

// ---------------------------------------------------------------------------
// Weather
// ---------------------------------------------------------------------------

/// An APRS weather report (DTI: _) or weather embedded in a position packet.
class WeatherPacket extends AprsPacket {
  final double? lat;
  final double? lon;
  final String symbolTable;
  final String symbolCode;

  /// Temperature in degrees Fahrenheit (as transmitted; convert for display).
  final double? temperature;

  /// Relative humidity 0-100 %.
  final int? humidity;

  /// Barometric pressure in millibars / hPa.
  final double? pressure;

  /// Sustained wind speed in mph.
  final double? windSpeed;

  /// Wind direction in degrees true (0-360).
  final int? windDirection;

  /// Wind gust in mph.
  final double? windGust;

  /// Rainfall in the last hour, in hundredths of an inch.
  final double? rainfall1h;

  /// Rainfall in the last 24 hours, in hundredths of an inch.
  final double? rainfall24h;

  const WeatherPacket({
    required super.rawLine,
    required super.source,
    required super.destination,
    required super.path,
    required super.receivedAt,
    super.transportSource,
    this.lat,
    this.lon,
    this.symbolTable = '_',
    this.symbolCode = '_',
    this.temperature,
    this.humidity,
    this.pressure,
    this.windSpeed,
    this.windDirection,
    this.windGust,
    this.rainfall1h,
    this.rainfall24h,
  });
}

// ---------------------------------------------------------------------------
// Message
// ---------------------------------------------------------------------------

/// An APRS message packet (DTI: :).
class MessagePacket extends AprsPacket {
  /// The callsign this message is addressed to (padded to 9 chars in wire
  /// format; stored here already trimmed).
  final String addressee;

  /// The message text.
  final String message;

  /// Optional message ID (the `{NNN}` suffix), null if absent.
  final String? messageId;

  const MessagePacket({
    required super.rawLine,
    required super.source,
    required super.destination,
    required super.path,
    required super.receivedAt,
    super.transportSource,
    required this.addressee,
    required this.message,
    this.messageId,
  });
}

// ---------------------------------------------------------------------------
// Object
// ---------------------------------------------------------------------------

/// An APRS object report (DTI: ;).
class ObjectPacket extends AprsPacket {
  /// Object name, exactly 9 chars in wire format; stored trimmed.
  final String objectName;
  final double lat;
  final double lon;
  final String symbolTable;
  final String symbolCode;
  final String comment;

  /// True when the object is "alive" (asterisk in wire format), false when
  /// it has been killed (underscore).
  final bool isAlive;

  const ObjectPacket({
    required super.rawLine,
    required super.source,
    required super.destination,
    required super.path,
    required super.receivedAt,
    super.transportSource,
    required this.objectName,
    required this.lat,
    required this.lon,
    required this.symbolTable,
    required this.symbolCode,
    required this.comment,
    required this.isAlive,
  });
}

// ---------------------------------------------------------------------------
// Item
// ---------------------------------------------------------------------------

/// An APRS item report (DTI: )).
class ItemPacket extends AprsPacket {
  /// Item name, 3-9 chars.
  final String itemName;
  final double lat;
  final double lon;
  final String symbolTable;
  final String symbolCode;
  final String comment;

  /// True when the item is alive (`!`), false when killed (`_`).
  final bool isAlive;

  const ItemPacket({
    required super.rawLine,
    required super.source,
    required super.destination,
    required super.path,
    required super.receivedAt,
    super.transportSource,
    required this.itemName,
    required this.lat,
    required this.lon,
    required this.symbolTable,
    required this.symbolCode,
    required this.comment,
    required this.isAlive,
  });
}

// ---------------------------------------------------------------------------
// Status
// ---------------------------------------------------------------------------

/// An APRS status report (DTI: >).
class StatusPacket extends AprsPacket {
  final String status;

  /// Optional DHM/HMS timestamp encoded in the status field.
  final DateTime? timestamp;

  const StatusPacket({
    required super.rawLine,
    required super.source,
    required super.destination,
    required super.path,
    required super.receivedAt,
    super.transportSource,
    required this.status,
    this.timestamp,
  });
}

// ---------------------------------------------------------------------------
// Mic-E
// ---------------------------------------------------------------------------

/// A Mic-E compressed position/status packet (DTI: ` or ').
class MicEPacket extends AprsPacket {
  final double lat;
  final double lon;
  final double? altitude;
  final int? course;
  final double? speed;
  final String symbolTable;
  final String symbolCode;
  final String comment;

  /// Human-readable Mic-E status message decoded from the destination field
  /// (e.g. "En Route", "In Service", "Off Duty").
  final String micEMessage;

  const MicEPacket({
    required super.rawLine,
    required super.source,
    required super.destination,
    required super.path,
    required super.receivedAt,
    super.transportSource,
    required this.lat,
    required this.lon,
    this.altitude,
    this.course,
    this.speed,
    required this.symbolTable,
    required this.symbolCode,
    required this.comment,
    required this.micEMessage,
  });
}

// ---------------------------------------------------------------------------
// Unknown / catch-all
// ---------------------------------------------------------------------------

/// Returned for any packet that could not be decoded into a typed subclass.
///
/// The [reason] field explains why decoding failed (for debugging/logging).
/// [rawInfo] holds the info field if it could be extracted.
class UnknownPacket extends AprsPacket {
  final String reason;
  final String rawInfo;

  const UnknownPacket({
    required super.rawLine,
    required super.source,
    required super.destination,
    required super.path,
    required super.receivedAt,
    super.transportSource,
    required this.reason,
    this.rawInfo = '',
  });
}
