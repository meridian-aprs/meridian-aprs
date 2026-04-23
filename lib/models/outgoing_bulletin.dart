/// A bulletin the operator is transmitting. Scheduled on a fixed interval by
/// [BulletinScheduler] until [expiresAt] or until disabled. See ADR-057.
library;

class OutgoingBulletin {
  OutgoingBulletin({
    required this.id,
    required this.addressee,
    required this.body,
    required this.intervalSeconds,
    required this.expiresAt,
    required this.createdAt,
    this.lastTransmittedAt,
    this.transmissionCount = 0,
    this.viaRf = true,
    this.viaAprsIs = true,
    this.enabled = true,
  });

  final int id;

  /// Full wire addressee, e.g. `BLN0`, `BLN1WX`.
  final String addressee;

  /// Up to 67 chars.
  final String body;

  /// 0 = one-shot (sent once then sits idle until expiry). Otherwise the
  /// expected spacing between transmissions: 300 / 600 / 900 / 1800 / 3600.
  final int intervalSeconds;

  final DateTime expiresAt;
  final DateTime createdAt;
  final DateTime? lastTransmittedAt;
  final int transmissionCount;

  final bool viaRf;
  final bool viaAprsIs;

  /// False after expiry (sweep disables) or after the user disables manually.
  final bool enabled;

  bool get isOneShot => intervalSeconds == 0;

  OutgoingBulletin copyWith({
    String? addressee,
    String? body,
    int? intervalSeconds,
    DateTime? expiresAt,
    DateTime? lastTransmittedAt,
    bool clearLastTransmittedAt = false,
    int? transmissionCount,
    bool? viaRf,
    bool? viaAprsIs,
    bool? enabled,
  }) => OutgoingBulletin(
    id: id,
    addressee: addressee ?? this.addressee,
    body: body ?? this.body,
    intervalSeconds: intervalSeconds ?? this.intervalSeconds,
    expiresAt: expiresAt ?? this.expiresAt,
    createdAt: createdAt,
    lastTransmittedAt: clearLastTransmittedAt
        ? null
        : (lastTransmittedAt ?? this.lastTransmittedAt),
    transmissionCount: transmissionCount ?? this.transmissionCount,
    viaRf: viaRf ?? this.viaRf,
    viaAprsIs: viaAprsIs ?? this.viaAprsIs,
    enabled: enabled ?? this.enabled,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'addressee': addressee,
    'body': body,
    'intervalSeconds': intervalSeconds,
    'expiresAt': expiresAt.millisecondsSinceEpoch,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'lastTransmittedAt': lastTransmittedAt?.millisecondsSinceEpoch,
    'transmissionCount': transmissionCount,
    'viaRf': viaRf,
    'viaAprsIs': viaAprsIs,
    'enabled': enabled,
  };

  factory OutgoingBulletin.fromJson(Map<String, dynamic> json) =>
      OutgoingBulletin(
        id: json['id'] as int,
        addressee: json['addressee'] as String,
        body: json['body'] as String,
        intervalSeconds: (json['intervalSeconds'] as int?) ?? 1800,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          (json['expiresAt'] as int?) ?? 0,
        ),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (json['createdAt'] as int?) ?? 0,
        ),
        lastTransmittedAt: (json['lastTransmittedAt'] as int?) == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                json['lastTransmittedAt'] as int,
              ),
        transmissionCount: (json['transmissionCount'] as int?) ?? 0,
        viaRf: (json['viaRf'] as bool?) ?? true,
        viaAprsIs: (json['viaAprsIs'] as bool?) ?? true,
        enabled: (json['enabled'] as bool?) ?? true,
      );
}
