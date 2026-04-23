/// Integration tests covering `MessageService` routing by classification
/// category (direct / group / bulletin). Complements the unit tests in
/// `addressee_matcher_test.dart` by confirming the service honors the
/// matcher's decision — ACKs go out for direct exact-match only, bulletins
/// land in the bulletin store, groups don't ACK. See ADR-055.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meridian_aprs/core/callsign/callsign_utils.dart';
import 'package:meridian_aprs/core/connection/connection_registry.dart';
import 'package:meridian_aprs/core/packet/aprs_packet.dart';
import 'package:meridian_aprs/models/message_category.dart';
import 'package:meridian_aprs/services/bulletin_service.dart';
import 'package:meridian_aprs/services/bulletin_subscription_service.dart';
import 'package:meridian_aprs/services/group_subscription_service.dart';
import 'package:meridian_aprs/services/message_service.dart';
import 'package:meridian_aprs/services/station_service.dart';
import 'package:meridian_aprs/services/station_settings_service.dart';
import 'package:meridian_aprs/services/tx_service.dart';

import '../helpers/fake_secure_credential_store.dart';

// ---------------------------------------------------------------------------
// Fixture
// ---------------------------------------------------------------------------

class _Fixture {
  _Fixture._({
    required this.service,
    required this.stationService,
    required this.sentLines,
    required this.groupSubscriptions,
    required this.bulletinSubscriptions,
    required this.bulletins,
  });

  final MessageService service;
  final StationService stationService;
  final List<String> sentLines;
  final GroupSubscriptionService groupSubscriptions;
  final BulletinSubscriptionService bulletinSubscriptions;
  final BulletinService bulletins;

  static Future<_Fixture> create({
    String callsign = 'W1ABC',
    int ssid = 7,
  }) async {
    SharedPreferences.setMockInitialValues({
      'user_callsign': callsign,
      'user_ssid': ssid,
      'message_id_counter': 0,
    });
    final prefs = await SharedPreferences.getInstance();
    final settings = StationSettingsService(
      prefs,
      store: FakeSecureCredentialStore(),
    );
    final stationService = StationService();
    final registry = ConnectionRegistry();
    final sentLines = <String>[];
    final txService = _RecordingTxService(registry, settings, sentLines);

    final groupSubs = GroupSubscriptionService(prefs: prefs);
    await groupSubs.load();

    final bulletinSubs = BulletinSubscriptionService(prefs: prefs);
    await bulletinSubs.load();

    final bulletins = BulletinService(
      subscriptions: bulletinSubs,
      prefs: prefs,
    );
    await bulletins.load();

    final service = MessageService(
      settings,
      txService,
      stationService,
      groupSubscriptions: groupSubs,
      bulletins: bulletins,
    );

    return _Fixture._(
      service: service,
      stationService: stationService,
      sentLines: sentLines,
      groupSubscriptions: groupSubs,
      bulletinSubscriptions: bulletinSubs,
      bulletins: bulletins,
    );
  }
}

class _RecordingTxService extends TxService {
  _RecordingTxService(super.registry, super.settings, this._log);
  final List<String> _log;

  @override
  Future<void> sendLine(String line, {ConnectionType? forceVia}) async =>
      _log.add(line);
}

// Helper: shove an APRS-IS message line through the ingest pipeline.
void _ingestLine(_Fixture f, String line) {
  f.stationService.ingestLine(line, source: PacketSource.aprsIs);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('direct classification', () {
    test('exact-match direct message is stored and ACKed', () async {
      final f = await _Fixture.create();
      _ingestLine(f, 'K2ABC>APMDN0,TCPIP*::W1ABC-7  :Hello{042');
      // Allow the stream listener microtask to fire.
      await Future<void>.delayed(Duration.zero);

      final conv = f.service.conversationWith('K2ABC');
      expect(conv, isNotNull);
      expect(conv!.messages.first.text, 'Hello');
      expect(conv.messages.first.category, MessageCategory.direct);

      // ACK was transmitted to K2ABC for msg id 042.
      expect(f.sentLines.any((l) => l.contains(':K2ABC')), isTrue);
      expect(f.sentLines.any((l) => l.contains('ack042')), isTrue);
    });

    test('cross-SSID direct is stored but not ACKed (ADR-054)', () async {
      final f = await _Fixture.create();
      // Addressed to W1ABC-9 — operator is W1ABC-7 — cross-SSID match.
      _ingestLine(f, 'K2ABC>APMDN0,TCPIP*::W1ABC-9  :Hello{042');
      await Future<void>.delayed(Duration.zero);

      final conv = f.service.conversationWith('K2ABC');
      expect(conv, isNotNull);
      expect(conv!.messages.first.isCrossSsid(f.service.myFullAddress), isTrue);
      // No ACK line emitted.
      expect(f.sentLines.where((l) => l.contains('ack042')), isEmpty);
    });
  });

  group('bulletin classification', () {
    test(
      'general bulletin (BLN0) lands in BulletinService, not Conversation',
      () async {
        final f = await _Fixture.create();
        _ingestLine(f, 'K5WX-15>APMDN0,TCPIP*::BLN0     :Severe wx alert');
        await Future<void>.delayed(Duration.zero);

        expect(f.bulletins.bulletins, hasLength(1));
        final b = f.bulletins.bulletins.first;
        expect(b.sourceCallsign, 'K5WX-15');
        expect(b.addressee, 'BLN0');
        expect(b.body, 'Severe wx alert');
        expect(b.heardCount, 1);

        // No conversation thread was created.
        expect(
          f.service.allConversations.any((c) => c.peerCallsign == 'K5WX-15'),
          isFalse,
        );
        // No ACK (bulletins are never ACKed).
        expect(f.sentLines, isEmpty);
      },
    );

    test('named bulletin with no subscription is dropped', () async {
      final f = await _Fixture.create();
      _ingestLine(f, 'K5WX-15>APMDN0,TCPIP*::BLN1WX   :Radar');
      await Future<void>.delayed(Duration.zero);
      expect(f.bulletins.bulletins, isEmpty);
    });

    test('named bulletin with matching subscription is kept', () async {
      final f = await _Fixture.create();
      await f.bulletinSubscriptions.add(groupName: 'WX', notify: false);
      _ingestLine(f, 'K5WX-15>APMDN0,TCPIP*::BLN1WX   :Radar');
      await Future<void>.delayed(Duration.zero);
      expect(f.bulletins.bulletins, hasLength(1));
      expect(f.bulletins.bulletins.first.groupName, 'WX');
    });
  });

  group('group classification', () {
    test('CQ message lands in a group conversation and is not ACKed', () async {
      final f = await _Fixture.create();
      // CQ is enabled by default in the seeded built-ins.
      _ingestLine(f, 'K2ABC>APMDN0,TCPIP*::CQ       :CQ CQ CQ');
      await Future<void>.delayed(Duration.zero);

      // Group thread keyed by `#GROUP:CQ`. Internal key is not public API
      // but we can verify via allConversations that a thread was created.
      final matched = f.service.allConversations
          .where((c) => c.peerCallsign.contains('CQ'))
          .toList();
      expect(matched, isNotEmpty);
      expect(matched.first.messages.first.category, MessageCategory.group);
      expect(matched.first.messages.first.groupName, 'CQ');

      // No ACK even though the wire carries a messageId (groups never ACK).
      expect(f.sentLines, isEmpty);
    });

    test('disabled group subscription does not match', () async {
      final f = await _Fixture.create();
      // Disable CQ.
      final cq = f.groupSubscriptions.subscriptions.firstWhere(
        (s) => s.name == 'CQ',
      );
      await f.groupSubscriptions.update(cq.id, enabled: false);

      _ingestLine(f, 'K2ABC>APMDN0,TCPIP*::CQ       :CQ CQ CQ');
      await Future<void>.delayed(Duration.zero);

      // No conversation, no bulletin, no ACK.
      expect(
        f.service.allConversations.any((c) => c.peerCallsign.contains('CQ')),
        isFalse,
      );
      expect(f.bulletins.bulletins, isEmpty);
      expect(f.sentLines, isEmpty);
    });
  });

  group('callsign normalization', () {
    test('stripSsid and normalizeCallsign still behave correctly', () {
      // Sanity: the matcher's direct rule relies on these primitives.
      expect(stripSsid('W1ABC-9'), 'W1ABC');
      expect(normalizeCallsign('W1ABC-0'), 'W1ABC');
      expect(normalizeCallsign('W1ABC'), 'W1ABC');
    });
  });
}
