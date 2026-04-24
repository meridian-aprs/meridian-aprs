/// Subscription to a named bulletin group (e.g. `BLNxWX`, `BLNxCLUB`).
///
/// Governs whether `BLNxNAME`-form bulletins for that group are kept on
/// receive. General `BLN0`–`BLN9` bulletins are not governed by subscriptions
/// — they use distance/radius logic instead. See ADR-058.
library;

class BulletinSubscription {
  BulletinSubscription({
    required this.id,
    required String groupName,
    this.notify = true,
    DateTime? createdAt,
  }) : groupName = groupName.toUpperCase(),
       createdAt = createdAt ?? DateTime.now();

  final int id;

  /// 1–5 uppercase alphanumeric characters (maximum the APRS 9-char addressee
  /// can carry after `BLN` + line number).
  final String groupName;

  final bool notify;
  final DateTime createdAt;

  static final RegExp namePattern = RegExp(r'^[A-Z0-9]{1,5}$');

  static bool isValidName(String name) => namePattern.hasMatch(name);

  BulletinSubscription copyWith({String? groupName, bool? notify}) =>
      BulletinSubscription(
        id: id,
        groupName: groupName ?? this.groupName,
        notify: notify ?? this.notify,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'groupName': groupName,
    'notify': notify,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  factory BulletinSubscription.fromJson(Map<String, dynamic> json) =>
      BulletinSubscription(
        id: json['id'] as int,
        groupName: json['groupName'] as String,
        notify: (json['notify'] as bool?) ?? true,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (json['createdAt'] as int?) ?? 0,
        ),
      );
}
