/// Precedence tests for the addressee matcher. These tests protect the
/// load-bearing ordering rule — if any of them regress, ACKs can be skipped
/// or sent to the wrong target. Do not change precedence without updating
/// ADR-055.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:meridian_aprs/core/callsign/addressee_matcher.dart';
import 'package:meridian_aprs/core/callsign/message_classification.dart';
import 'package:meridian_aprs/core/callsign/operator_identity.dart';
import 'package:meridian_aprs/models/bulletin.dart';
import 'package:meridian_aprs/models/group_subscription.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

OperatorIdentity _operator(String callsign, [int ssid = 0]) =>
    OperatorIdentity(callsign: callsign, ssid: ssid);

GroupSubscription _group(
  int id,
  String name, {
  MatchMode matchMode = MatchMode.prefix,
  bool enabled = true,
}) => GroupSubscription(
  id: id,
  name: name,
  matchMode: matchMode,
  enabled: enabled,
  notify: false,
  replyMode: ReplyMode.sender,
);

MessageClassification _classify(
  String addressee,
  OperatorIdentity identity,
  List<GroupSubscription> subs,
) => AddresseeMatcher.classifyWithPrecedence(addressee, identity, subs);

// ---------------------------------------------------------------------------
// Spec §11 required tests
// ---------------------------------------------------------------------------

void main() {
  group('ADR-055 precedence: Bulletin → Direct → Group', () {
    test('bulletin beats pathological group with B prefix', () {
      // Group `B` prefix would match `BLN0` if we let it — but bulletins
      // are classified first, so `BLN0` is a bulletin.
      final identity = _operator('W1ABC', 7);
      final subs = [_group(1, 'B')];
      final result = _classify('BLN0', identity, subs);
      expect(result, isA<BulletinClassification>());
      final info = (result as BulletinClassification).info;
      expect(info.category, BulletinCategory.general);
      expect(info.lineNumber, '0');
      expect(info.groupName, isNull);
    });

    test('bulletin beats named-overlap group (BLN1CLUB + CLUB group)', () {
      final identity = _operator('W1ABC', 7);
      final subs = [_group(1, 'CLUB')];
      final result = _classify('BLN1CLUB', identity, subs);
      expect(result, isA<BulletinClassification>());
      final info = (result as BulletinClassification).info;
      expect(info.category, BulletinCategory.groupNamed);
      expect(info.lineNumber, '1');
      expect(info.groupName, 'CLUB');
    });

    test('direct beats group prefix conflict (W1ABC-7 + group W1 prefix)', () {
      // This is the load-bearing case — if group came first, W1 prefix would
      // capture a direct message, skip the ACK, sender's retry never
      // terminates, operator appears unreachable.
      final identity = _operator('W1ABC', 7);
      final subs = [_group(1, 'W1')];
      final result = _classify('W1ABC-7', identity, subs);
      expect(result, isA<DirectClassification>());
      expect((result as DirectClassification).isExactMatch, isTrue);
    });

    test('direct beats group exact conflict (W1ABC + group W1ABC exact)', () {
      final identity = _operator('W1ABC', 0);
      final subs = [_group(1, 'W1ABC', matchMode: MatchMode.exact)];
      final result = _classify('W1ABC', identity, subs);
      expect(result, isA<DirectClassification>());
      expect((result as DirectClassification).isExactMatch, isTrue);
    });

    test('group matches when no direct/bulletin (addressee CQ, group CQ)', () {
      final identity = _operator('W1ABC', 7);
      final subs = [_group(1, 'CQ')];
      final result = _classify('CQ', identity, subs);
      expect(result, isA<GroupClassification>());
      expect((result as GroupClassification).subscription.name, 'CQ');
    });

    test('first subscription match wins (CQFOO with CQ then CQFOO subs)', () {
      // Both groups are prefix-mode. CQ comes first in the list, so it wins.
      final identity = _operator('W1ABC', 7);
      final subs = [_group(1, 'CQ'), _group(2, 'CQFOO')];
      final result = _classify('CQFOO', identity, subs);
      expect(result, isA<GroupClassification>());
      expect((result as GroupClassification).subscription.name, 'CQ');
    });

    test('disabled subscriptions do not match', () {
      final identity = _operator('W1ABC', 7);
      final subs = [_group(1, 'CQ', enabled: false)];
      // Matcher callers pre-filter by `.enabledSubscriptions`, so disabled
      // subs never reach the matcher. Both the full-list and enabled-only
      // paths should classify as none.
      final noneFromFull = _classify('CQ', identity, subs);
      final noneFromFiltered = _classify(
        'CQ',
        identity,
        subs.where((s) => s.enabled).toList(),
      );
      expect(noneFromFull, isA<NoneClassification>());
      expect(noneFromFiltered, isA<NoneClassification>());
    });

    test('exact mode rejects longer addressee (CQRS with group CQ exact)', () {
      final identity = _operator('W1ABC', 7);
      final subs = [_group(1, 'CQ', matchMode: MatchMode.exact)];
      final result = _classify('CQRS', identity, subs);
      expect(result, isA<NoneClassification>());
    });

    test('prefix mode accepts longer (CQRS with group CQ prefix)', () {
      final identity = _operator('W1ABC', 7);
      final subs = [_group(1, 'CQ')];
      final result = _classify('CQRS', identity, subs);
      expect(result, isA<GroupClassification>());
      expect((result as GroupClassification).subscription.name, 'CQ');
    });
  });

  // -------------------------------------------------------------------------
  // Edge cases beyond spec §11
  // -------------------------------------------------------------------------

  group('edge cases', () {
    test('empty operator (pre-onboarding) falls through direct', () {
      final identity = _operator('', 0);
      final subs = [_group(1, 'CQ')];
      final result = _classify('CQ', identity, subs);
      // Should still hit the group rule since direct requires a real
      // callsign, and shouldn't throw.
      expect(result, isA<GroupClassification>());
    });

    test('empty operator + direct-looking addressee → none', () {
      final identity = _operator('', 0);
      final result = _classify('W1ABC', identity, []);
      expect(result, isA<NoneClassification>());
    });

    test(
      'cross-SSID direct: W1ABC-9 to operator W1ABC-7 is direct, not exact',
      () {
        final identity = _operator('W1ABC', 7);
        final result = _classify('W1ABC-9', identity, []);
        expect(result, isA<DirectClassification>());
        expect((result as DirectClassification).isExactMatch, isFalse);
      },
    );

    test('-0 normalization: W1ABC-0 to operator W1ABC is exact match', () {
      final identity = _operator('W1ABC', 0);
      final result = _classify('W1ABC-0', identity, []);
      expect(result, isA<DirectClassification>());
      expect((result as DirectClassification).isExactMatch, isTrue);
    });

    test('nothing matches → none', () {
      final identity = _operator('W1ABC', 7);
      final subs = [_group(1, 'CQ')];
      final result = _classify('KB1XYZ', identity, subs);
      expect(result, isA<NoneClassification>());
    });

    test('padded 9-char addressee is trimmed', () {
      // Wire-form addressees are 9-char space-padded; the matcher trims.
      final identity = _operator('W1ABC', 7);
      final result = _classify('W1ABC-7  ', identity, []);
      expect(result, isA<DirectClassification>());
    });

    test('general bulletin with digit line parses correctly (BLN9)', () {
      final result = _classify('BLN9', _operator('W1ABC', 7), []);
      expect(result, isA<BulletinClassification>());
      final info = (result as BulletinClassification).info;
      expect(info.category, BulletinCategory.general);
      expect(info.lineNumber, '9');
      expect(info.groupName, isNull);
    });

    test('named bulletin with letter line parses correctly (BLNACLUB)', () {
      final result = _classify('BLNACLUB', _operator('W1ABC', 7), []);
      expect(result, isA<BulletinClassification>());
      final info = (result as BulletinClassification).info;
      expect(info.category, BulletinCategory.groupNamed);
      expect(info.lineNumber, 'A');
      expect(info.groupName, 'CLUB');
    });
  });
}
