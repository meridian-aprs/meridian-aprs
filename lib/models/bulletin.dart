/// A received APRS bulletin, stored separately from [MessageEntry] because
/// retransmissions update (not duplicate) existing rows and aging is based on
/// `lastHeardAt` rather than arrival sequence. See ADR-057.
library;

import '../core/packet/aprs_packet.dart';

/// Which side of the addressee space the bulletin lives on.
///
/// [general] — `BLN0`–`BLN9`; delivery scope controlled by distance/radius.
/// [groupNamed] — `BLNxNAME`; delivery scope controlled by subscriptions.
enum BulletinCategory { general, groupNamed }

/// Transport that delivered a given receipt of a bulletin. Reduced from
/// [PacketSource] so the model stays free of connection-type distinctions the
/// bulletin UI doesn't need (BLE vs serial TNC both count as RF).
enum BulletinTransport { rf, aprsIs }

extension BulletinTransportMapping on PacketSource {
  BulletinTransport get asBulletinTransport => switch (this) {
    PacketSource.aprsIs => BulletinTransport.aprsIs,
    PacketSource.bleTnc ||
    PacketSource.serialTnc ||
    PacketSource.tnc => BulletinTransport.rf,
  };
}

/// A received bulletin row. Unique on `(sourceCallsign, addressee)` —
/// retransmissions of the same addressee from the same source update this
/// row rather than append.
class Bulletin {
  Bulletin({
    required this.id,
    required this.sourceCallsign,
    required this.addressee,
    required this.category,
    required this.lineNumber,
    required this.body,
    required this.firstHeardAt,
    required this.lastHeardAt,
    required this.heardCount,
    required this.transports,
    this.groupName,
    this.receivedLat,
    this.receivedLon,
    this.isRead = false,
  });

  final int id;
  final String sourceCallsign;

  /// Full wire addressee, e.g. `BLN0`, `BLN1WX`. Already trimmed.
  final String addressee;

  final BulletinCategory category;

  /// `"0"`–`"9"` for general, `"0"`–`"Z"` (alphanumeric) for group-named.
  final String lineNumber;

  /// `"WX"` for `BLN1WX`; null for `BLN0`–`BLN9`.
  final String? groupName;

  final String body;
  final DateTime firstHeardAt;
  final DateTime lastHeardAt;

  /// Aggregate counter; not a per-receipt array (ADR-057).
  final int heardCount;

  /// Transports we have observed delivering this bulletin (may accumulate
  /// over multiple retransmissions, e.g. both RF and APRS-IS).
  final Set<BulletinTransport> transports;

  /// Receiver's own position at the time of ingest. Null for RF receipts and
  /// for APRS-IS receipts when the operator has no station location set.
  final double? receivedLat;
  final double? receivedLon;

  final bool isRead;

  Bulletin copyWith({
    String? body,
    DateTime? lastHeardAt,
    int? heardCount,
    Set<BulletinTransport>? transports,
    double? receivedLat,
    double? receivedLon,
    bool? isRead,
  }) => Bulletin(
    id: id,
    sourceCallsign: sourceCallsign,
    addressee: addressee,
    category: category,
    lineNumber: lineNumber,
    groupName: groupName,
    body: body ?? this.body,
    firstHeardAt: firstHeardAt,
    lastHeardAt: lastHeardAt ?? this.lastHeardAt,
    heardCount: heardCount ?? this.heardCount,
    transports: transports ?? this.transports,
    receivedLat: receivedLat ?? this.receivedLat,
    receivedLon: receivedLon ?? this.receivedLon,
    isRead: isRead ?? this.isRead,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceCallsign': sourceCallsign,
    'addressee': addressee,
    'category': category.name,
    'lineNumber': lineNumber,
    'groupName': groupName,
    'body': body,
    'firstHeardAt': firstHeardAt.millisecondsSinceEpoch,
    'lastHeardAt': lastHeardAt.millisecondsSinceEpoch,
    'heardCount': heardCount,
    'transports': transports.map((t) => t.name).toList(),
    'receivedLat': receivedLat,
    'receivedLon': receivedLon,
    'isRead': isRead,
  };

  factory Bulletin.fromJson(Map<String, dynamic> json) => Bulletin(
    id: json['id'] as int,
    sourceCallsign: json['sourceCallsign'] as String,
    addressee: json['addressee'] as String,
    category: BulletinCategory.values.firstWhere(
      (c) => c.name == (json['category'] as String?),
      orElse: () => BulletinCategory.general,
    ),
    lineNumber: json['lineNumber'] as String,
    groupName: json['groupName'] as String?,
    body: json['body'] as String,
    firstHeardAt: DateTime.fromMillisecondsSinceEpoch(
      (json['firstHeardAt'] as int?) ?? 0,
    ),
    lastHeardAt: DateTime.fromMillisecondsSinceEpoch(
      (json['lastHeardAt'] as int?) ?? 0,
    ),
    heardCount: (json['heardCount'] as int?) ?? 1,
    transports: ((json['transports'] as List?) ?? [])
        .whereType<String>()
        .map(
          (name) => BulletinTransport.values.firstWhere(
            (t) => t.name == name,
            orElse: () => BulletinTransport.rf,
          ),
        )
        .toSet(),
    receivedLat: (json['receivedLat'] as num?)?.toDouble(),
    receivedLon: (json['receivedLon'] as num?)?.toDouble(),
    isRead: (json['isRead'] as bool?) ?? false,
  );
}

/// Structured view of a parsed bulletin addressee.
///
/// `BLN0`        → line=`"0"`, category=[BulletinCategory.general],      groupName=null
/// `BLN1WX`      → line=`"1"`, category=[BulletinCategory.groupNamed],   groupName=`"WX"`
/// `BLNASRARC`   → line=`"A"`, category=[BulletinCategory.groupNamed],   groupName=`"SRARC"`
class BulletinAddresseeInfo {
  const BulletinAddresseeInfo({
    required this.addressee,
    required this.lineNumber,
    required this.category,
    this.groupName,
  });

  final String addressee;
  final String lineNumber;
  final BulletinCategory category;
  final String? groupName;
}
