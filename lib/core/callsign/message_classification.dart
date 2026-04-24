/// Result of [AddresseeMatcher.classifyWithPrecedence]. The classification
/// determines UI routing, storage (Conversation vs. Bulletin), and — most
/// importantly — whether an ACK should be sent.
///
/// Do not fold this into a boolean or flatten to a flag enum. The concrete
/// subtypes carry information downstream handlers need (the matched
/// subscription, the parsed bulletin info, the exact-vs-cross-SSID
/// distinction for ACK eligibility).
///
/// See ADR-055.
library;

import '../../models/bulletin.dart';
import '../../models/group_subscription.dart';

sealed class MessageClassification {
  const MessageClassification();
}

/// The addressee is a bulletin (`BLN[0-9A-Z]…`). Never ACKed.
class BulletinClassification extends MessageClassification {
  const BulletinClassification(this.info);
  final BulletinAddresseeInfo info;
}

/// The addressee targets the operator's own callsign (any SSID form per
/// ADR-054). [isExactMatch] governs ACK eligibility — exact matches get ACKed,
/// cross-SSID matches never do.
class DirectClassification extends MessageClassification {
  const DirectClassification({required this.isExactMatch});
  final bool isExactMatch;
}

/// The addressee matches an enabled [GroupSubscription]. Never ACKed.
class GroupClassification extends MessageClassification {
  const GroupClassification(this.subscription);
  final GroupSubscription subscription;
}

/// The addressee did not match any rule. Drop the packet.
class NoneClassification extends MessageClassification {
  const NoneClassification();
}
