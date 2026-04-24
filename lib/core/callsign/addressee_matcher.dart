/// Addressee classifier for incoming APRS message packets.
///
/// Applies three rules in a fixed, load-bearing order:
///
///   1. **Bulletin** — syntactic match on `BLN[0-9A-Z]…`
///   2. **Direct** — matches the operator's own callsign (any SSID, v0.14)
///   3. **Group**   — matches any enabled [GroupSubscription]
///
/// The order is not a style preference. Reordering it causes protocol
/// violations. If a message to `W1ABC-7` (operator `W1ABC`) classifies as a
/// group before it classifies as direct, the code below will not ACK it —
/// the sender's retry loop then never terminates and the operator appears
/// unreachable despite receiving.
///
/// **Do not reorder. Do not collapse into a single matcher list. Do not
/// rename to `classify()`.** The method name is part of the contract — it
/// signals intent to future contributors. If a refactor looks cleaner by
/// reordering these rules, stop and re-read ADR-055 before writing code.
///
/// See `docs/DECISIONS.md` ADR-055 for the full rationale, the required test
/// cases in `test/core/callsign/addressee_matcher_test.dart`, and ADR-054 for
/// the underlying direct-match rules (exact + cross-SSID, `-0` normalized).
library;

import '../../models/bulletin.dart';
import '../../models/group_subscription.dart';
import 'message_classification.dart';
import 'operator_identity.dart';

class AddresseeMatcher {
  AddresseeMatcher._();

  /// Matches `BLN` + line character (digit 0–9 or letter A–Z) as the first
  /// four characters. Any addressee starting with this prefix is a bulletin
  /// — no legitimate callsign has this shape, so the syntactic test is safe.
  static final RegExp _bulletinPattern = RegExp(r'^BLN[0-9A-Z]');

  /// Classifies an incoming message addressee using strict precedence:
  /// Bulletin > Direct > Group. This ordering is load-bearing for ACK
  /// correctness — see ADR-055. Do not reorder without updating the ADR.
  ///
  /// [addressee] is the raw wire field (trailing spaces permitted). [identity]
  /// is the operator's current [OperatorIdentity] snapshot. [enabledSubscriptions]
  /// is evaluated in list order; first-match-wins.
  static MessageClassification classifyWithPrecedence(
    String addressee,
    OperatorIdentity identity,
    List<GroupSubscription> enabledSubscriptions,
  ) {
    final normalized = addressee.trim().toUpperCase();

    // 1. Bulletin — syntactic; cannot conflict with callsigns.
    if (_bulletinPattern.hasMatch(normalized)) {
      return BulletinClassification(_parseBulletinAddressee(normalized));
    }

    // 2. Direct — ACK-required (v0.14 rules).
    if (identity.matchesOwnCallsign(normalized)) {
      return DirectClassification(
        isExactMatch: identity.matchesExactly(normalized),
      );
    }

    // 3. Group — user-configurable; lowest precedence.
    for (final sub in enabledSubscriptions) {
      if (sub.matches(normalized)) {
        return GroupClassification(sub);
      }
    }

    return const NoneClassification();
  }

  /// Parses an already-validated bulletin addressee into structured fields.
  ///
  /// `BLN0`      → line=`"0"`, general
  /// `BLN1WX`    → line=`"1"`, groupNamed, group=`"WX"`
  /// `BLNASRARC` → line=`"A"`, groupNamed, group=`"SRARC"`
  static BulletinAddresseeInfo _parseBulletinAddressee(String addressee) {
    // Guaranteed: length >= 4, matches `^BLN[0-9A-Z]`.
    final line = addressee.substring(3, 4);
    final rest = addressee.length > 4 ? addressee.substring(4) : '';
    final isGeneral = rest.isEmpty && RegExp(r'^[0-9]$').hasMatch(line);
    return BulletinAddresseeInfo(
      addressee: addressee,
      lineNumber: line,
      category: isGeneral
          ? BulletinCategory.general
          : BulletinCategory.groupNamed,
      groupName: isGeneral ? null : rest,
    );
  }
}
