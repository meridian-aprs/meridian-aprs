/// Subscription to an APRS message group (e.g. `CQ`, `QST`, `ALL`, `CLUB`).
///
/// Groups are a pure client-side receiver filter — APRS has no server-side
/// group mechanism, so "subscription" just means "include packets whose
/// addressee matches this group's name in the Groups view."
///
/// See ADR-056.
library;

/// How the group's [name] is matched against an incoming addressee.
///
/// APRS wire addressees are 9 characters (space-padded). Yaesu radios emit
/// `ALL******` (prefix-style) so [prefix] is the default; [exact] is available
/// for clubs that want strict match.
enum MatchMode { prefix, exact }

/// Where a reply composed inside a group channel goes by default.
///
/// [sender] — reply addressed to the last-heard sender of the group message
/// (discovery/announcement pattern; CQ, QST, ALL default to this).
/// [group]  — reply broadcast to the group itself (club chat-room pattern;
/// custom groups default to this).
enum ReplyMode { sender, group }

class GroupSubscription {
  GroupSubscription({
    required this.id,
    required String name,
    this.matchMode = MatchMode.prefix,
    this.enabled = true,
    this.notify = true,
    this.replyMode = ReplyMode.group,
    this.isBuiltin = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : name = name.toUpperCase(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  /// Stable local identifier. Assigned by [GroupSubscriptionService].
  final int id;

  /// 1–9 uppercase alphanumeric characters.
  final String name;

  final MatchMode matchMode;
  final bool enabled;
  final bool notify;
  final ReplyMode replyMode;

  /// True for the seeded built-ins (ALL, CQ, QST, YAESU). Built-ins can be
  /// disabled and have their notify/replyMode edited, but cannot be renamed
  /// or deleted.
  final bool isBuiltin;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Returns true when [addressee] matches this subscription's [name] per
  /// [matchMode]. Caller must pass an already-trimmed, uppercased addressee.
  bool matches(String addressee) {
    if (!enabled) return false;
    switch (matchMode) {
      case MatchMode.exact:
        return addressee == name;
      case MatchMode.prefix:
        return addressee.startsWith(name);
    }
  }

  /// RegExp for the allowed name shape (1–9 uppercase alphanumeric characters).
  static final RegExp namePattern = RegExp(r'^[A-Z0-9]{1,9}$');

  /// Returns true if [name] is a syntactically valid group name.
  static bool isValidName(String name) => namePattern.hasMatch(name);

  GroupSubscription copyWith({
    String? name,
    MatchMode? matchMode,
    bool? enabled,
    bool? notify,
    ReplyMode? replyMode,
    DateTime? updatedAt,
  }) => GroupSubscription(
    id: id,
    name: name ?? this.name,
    matchMode: matchMode ?? this.matchMode,
    enabled: enabled ?? this.enabled,
    notify: notify ?? this.notify,
    replyMode: replyMode ?? this.replyMode,
    isBuiltin: isBuiltin,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'matchMode': matchMode.name,
    'enabled': enabled,
    'notify': notify,
    'replyMode': replyMode.name,
    'isBuiltin': isBuiltin,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  factory GroupSubscription.fromJson(Map<String, dynamic> json) =>
      GroupSubscription(
        id: json['id'] as int,
        name: json['name'] as String,
        matchMode: MatchMode.values.firstWhere(
          (m) => m.name == (json['matchMode'] as String?),
          orElse: () => MatchMode.prefix,
        ),
        enabled: (json['enabled'] as bool?) ?? true,
        notify: (json['notify'] as bool?) ?? true,
        replyMode: ReplyMode.values.firstWhere(
          (m) => m.name == (json['replyMode'] as String?),
          orElse: () => ReplyMode.group,
        ),
        isBuiltin: (json['isBuiltin'] as bool?) ?? false,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (json['createdAt'] as int?) ?? 0,
        ),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (json['updatedAt'] as int?) ?? 0,
        ),
      );
}
