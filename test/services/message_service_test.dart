import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meridian_aprs/core/connection/connection_registry.dart';
import 'package:meridian_aprs/services/bulletin_service.dart';
import 'package:meridian_aprs/services/bulletin_subscription_service.dart';
import 'package:meridian_aprs/services/group_subscription_service.dart';
import 'package:meridian_aprs/services/message_service.dart';
import 'package:meridian_aprs/services/station_service.dart';
import 'package:meridian_aprs/services/station_settings_service.dart';
import 'package:meridian_aprs/services/tx_service.dart';

import '../helpers/fake_secure_credential_store.dart';

// ---------------------------------------------------------------------------
// Test fixture
// ---------------------------------------------------------------------------

/// Creates a fully-wired set of services for one test.
///
/// Uses [FakeTransport] so no network activity occurs. Returns a
/// [_Fixture] that exposes the [MessageService] and the list of lines
/// sent via [TxService] (intercepted via a subclass).
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
    String callsign = 'W1AW',
    int ssid = 9,
    int initialCounter = 0,
  }) async {
    SharedPreferences.setMockInitialValues({
      'user_callsign': callsign,
      'user_ssid': ssid,
      'message_id_counter': initialCounter,
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
    final messageService = MessageService(
      settings,
      txService,
      stationService,
      groupSubscriptions: groupSubs,
      bulletins: bulletins,
    );
    return _Fixture._(
      service: messageService,
      stationService: stationService,
      sentLines: sentLines,
      groupSubscriptions: groupSubs,
      bulletinSubscriptions: bulletinSubs,
      bulletins: bulletins,
    );
  }
}

/// TxService that records every outgoing line instead of sending.
class _RecordingTxService extends TxService {
  _RecordingTxService(super.registry, super.settings, this._log);
  final List<String> _log;

  @override
  Future<void> sendLine(String line, {ConnectionType? forceVia}) async =>
      _log.add(line);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // --- Message ID counter -------------------------------------------------

  group('message ID counter', () {
    test('starts at 001 when counter is 0', () async {
      final f = await _Fixture.create(initialCounter: 0);
      await f.service.sendMessage('KB1XYZ', 'Hello');
      expect(f.sentLines.last, contains('{001'));
    });

    test('uses next value when counter is non-zero', () async {
      final f = await _Fixture.create(initialCounter: 5);
      await f.service.sendMessage('KB1XYZ', 'Hello');
      expect(f.sentLines.last, contains('{006'));
    });

    test('increments on each send', () async {
      final f = await _Fixture.create(initialCounter: 0);
      await f.service.sendMessage('KB1XYZ', 'One');
      await f.service.sendMessage('KB1XYZ', 'Two');
      expect(f.sentLines[0], contains('{001'));
      expect(f.sentLines[1], contains('{002'));
    });

    test('wraps from 999 back to 001', () async {
      final f = await _Fixture.create(initialCounter: 999);
      await f.service.sendMessage('KB1XYZ', 'Wrap');
      expect(f.sentLines.last, contains('{001'));
    });
  });

  // --- Outbound message format --------------------------------------------

  group('outbound message format', () {
    test('pads addressee to 9 characters', () async {
      final f = await _Fixture.create();
      await f.service.sendMessage('WB4APR', 'Test');
      expect(f.sentLines.last, contains(':WB4APR   :'));
    });

    test('addressee is uppercased', () async {
      final f = await _Fixture.create();
      await f.service.sendMessage('kb1xyz', 'Hi');
      expect(f.sentLines.last, contains(':KB1XYZ   :'));
    });

    test('includes message text', () async {
      final f = await _Fixture.create();
      await f.service.sendMessage('KB1XYZ', 'Hello there');
      expect(f.sentLines.last, contains('Hello there'));
    });
  });

  // --- Conversation tracking ----------------------------------------------

  group('conversation tracking', () {
    test('creates conversation on first outbound message', () async {
      final f = await _Fixture.create();
      await f.service.sendMessage('KB1XYZ', 'Hi');
      expect(f.service.conversations.length, equals(1));
      expect(f.service.conversations.first.peerCallsign, equals('KB1XYZ'));
    });

    test('reuses conversation for subsequent messages to same peer', () async {
      final f = await _Fixture.create();
      await f.service.sendMessage('KB1XYZ', 'First');
      await f.service.sendMessage('KB1XYZ', 'Second');
      expect(f.service.conversations.length, equals(1));
      expect(f.service.conversations.first.messages.length, equals(2));
    });

    test('totalUnread starts at 0', () async {
      final f = await _Fixture.create();
      expect(f.service.totalUnread, equals(0));
    });

    test('markRead resets unread count', () async {
      final f = await _Fixture.create();
      // Inject inbound message directly via station service.
      f.stationService.ingestLine('KB1XYZ>APMDN0::W1AW-9   :Hello{042');
      await Future.delayed(const Duration(milliseconds: 50));

      if (f.service.totalUnread > 0) {
        f.service.markRead('KB1XYZ');
        expect(f.service.totalUnread, equals(0));
      }
    });
  });

  // --- ACK / REJ handling -------------------------------------------------

  group('ACK handling', () {
    test('outgoing message starts as pending', () async {
      final f = await _Fixture.create();
      await f.service.sendMessage('KB1XYZ', 'Test');
      final conv = f.service.conversationWith('KB1XYZ');
      expect(conv, isNotNull);
      expect(conv!.messages.first.status, equals(MessageStatus.pending));
    });

    test(
      'inbound ACK packet (parser isAck=true) marks message acked',
      () async {
        final f = await _Fixture.create(initialCounter: 0);
        // Send a message so there is an outgoing entry with wireId '001'.
        await f.service.sendMessage('KB1XYZ', 'Hello');
        // Inject the ACK packet from the remote station via station service.
        // Parser will set isAck=true and messageId='001' on the MessagePacket.
        f.stationService.ingestLine('KB1XYZ>APMDN0::W1AW-9   :ack001');
        await Future.delayed(const Duration(milliseconds: 50));

        final conv = f.service.conversationWith('KB1XYZ');
        expect(conv, isNotNull);
        final outgoing = conv!.messages.firstWhere((m) => m.isOutgoing);
        expect(outgoing.status, equals(MessageStatus.acked));
      },
    );

    test(
      'inbound REJ packet (parser isRej=true) marks message rejected',
      () async {
        final f = await _Fixture.create(initialCounter: 0);
        await f.service.sendMessage('KB1XYZ', 'Hello');
        // Inject the REJ packet.
        f.stationService.ingestLine('KB1XYZ>APMDN0::W1AW-9   :rej001');
        await Future.delayed(const Duration(milliseconds: 50));

        final conv = f.service.conversationWith('KB1XYZ');
        expect(conv, isNotNull);
        final outgoing = conv!.messages.firstWhere((m) => m.isOutgoing);
        expect(outgoing.status, equals(MessageStatus.rejected));
      },
    );
  });

  // --- Duplicate detection ------------------------------------------------

  group('duplicate detection', () {
    test('same source+wireId is not added twice', () async {
      final f = await _Fixture.create();
      const line = 'KB1XYZ>APMDN0::W1AW-9   :Hello{099';
      f.stationService.ingestLine(line);
      f.stationService.ingestLine(line);
      await Future.delayed(const Duration(milliseconds: 50));

      final conv = f.service.conversationWith('KB1XYZ');
      // Should only have one message, not two
      final inboundCount =
          conv?.messages
              .where((m) => !m.isOutgoing && m.wireId == '099')
              .length ??
          0;
      expect(inboundCount, lessThanOrEqualTo(1));
    });
  });

  // --- Cross-SSID message capture -----------------------------------------

  group('cross-SSID message capture', () {
    test('cross-SSID message is captured, no ACK sent', () async {
      // Station is W1AW-9; packet addressed to W1AW-7 (different SSID).
      final f = await _Fixture.create(callsign: 'W1AW', ssid: 9);
      final linesBefore = f.sentLines.length;

      f.stationService.ingestLine('KB1XYZ>APMDN0::W1AW-7   :Hello{042');
      await Future.delayed(const Duration(milliseconds: 50));

      final conv = f.service.conversationWith('KB1XYZ');
      expect(conv, isNotNull);
      expect(conv!.messages.where((m) => !m.isOutgoing).length, equals(1));
      // No ACK transmitted for cross-SSID.
      expect(f.sentLines.length, equals(linesBefore));
    });

    test('exact-match message is captured and ACK sent', () async {
      final f = await _Fixture.create(callsign: 'W1AW', ssid: 9);
      final linesBefore = f.sentLines.length;

      f.stationService.ingestLine('KB1XYZ>APMDN0::W1AW-9   :Hello{043');
      await Future.delayed(const Duration(milliseconds: 50));

      final conv = f.service.conversationWith('KB1XYZ');
      expect(conv, isNotNull);
      expect(conv!.messages.where((m) => !m.isOutgoing).length, equals(1));
      // ACK was transmitted.
      expect(f.sentLines.length, greaterThan(linesBefore));
      expect(f.sentLines.last, contains('ack043'));
    });

    test('cross-SSID entry has isCrossSsid true', () async {
      final f = await _Fixture.create(callsign: 'W1AW', ssid: 9);

      f.stationService.ingestLine('KB1XYZ>APMDN0::W1AW-7   :Hello{044');
      await Future.delayed(const Duration(milliseconds: 50));

      final conv = f.service.conversationWith('KB1XYZ');
      expect(conv, isNotNull);
      final entry = conv!.messages.firstWhere((m) => !m.isOutgoing);
      expect(entry.isCrossSsid(f.service.myFullAddress), isTrue);
    });

    test('exact-match entry has isCrossSsid false', () async {
      final f = await _Fixture.create(callsign: 'W1AW', ssid: 9);

      f.stationService.ingestLine('KB1XYZ>APMDN0::W1AW-9   :Hello{045');
      await Future.delayed(const Duration(milliseconds: 50));

      final conv = f.service.conversationWith('KB1XYZ');
      expect(conv, isNotNull);
      final entry = conv!.messages.firstWhere((m) => !m.isOutgoing);
      expect(entry.isCrossSsid(f.service.myFullAddress), isFalse);
    });

    test(
      '-0 equivalence: packet to W1AW-0 is exact match when station is W1AW',
      () async {
        // Station callsign W1AW, ssid 0 → fullAddress = 'W1AW' → myFullAddress = 'W1AW'.
        final f = await _Fixture.create(callsign: 'W1AW', ssid: 0);
        final linesBefore = f.sentLines.length;

        f.stationService.ingestLine('KB1XYZ>APMDN0::W1AW-0   :Hello{046');
        await Future.delayed(const Duration(milliseconds: 50));

        final conv = f.service.conversationWith('KB1XYZ');
        expect(conv, isNotNull);
        final entry = conv!.messages.firstWhere((m) => !m.isOutgoing);
        expect(entry.isCrossSsid(f.service.myFullAddress), isFalse);
        // ACK must have been sent (exact match).
        expect(f.sentLines.length, greaterThan(linesBefore));
      },
    );

    test(
      'no-SSID station + packet to W1AW-7 is cross-SSID capture, no ACK',
      () async {
        final f = await _Fixture.create(callsign: 'W1AW', ssid: 0);
        final linesBefore = f.sentLines.length;

        f.stationService.ingestLine('KB1XYZ>APMDN0::W1AW-7   :Hello{047');
        await Future.delayed(const Duration(milliseconds: 50));

        final conv = f.service.conversationWith('KB1XYZ');
        expect(conv, isNotNull);
        final entry = conv!.messages.firstWhere((m) => !m.isOutgoing);
        expect(entry.isCrossSsid(f.service.myFullAddress), isTrue);
        expect(f.sentLines.length, equals(linesBefore));
      },
    );

    test(
      'showOtherSsids false hides cross-SSID-only thread from conversations',
      () async {
        final f = await _Fixture.create(callsign: 'W1AW', ssid: 9);
        // Default showOtherSsids is false.
        expect(f.service.showOtherSsids, isFalse);

        f.stationService.ingestLine('KB1XYZ>APMDN0::W1AW-7   :Hello{048');
        await Future.delayed(const Duration(milliseconds: 50));

        // Cross-SSID-only thread must not appear in filtered conversations.
        expect(
          f.service.conversations.any((c) => c.peerCallsign == 'KB1XYZ'),
          isFalse,
        );
      },
    );

    test('showOtherSsids false, mixed thread is visible', () async {
      final f = await _Fixture.create(callsign: 'W1AW', ssid: 9);

      // One cross-SSID message.
      f.stationService.ingestLine('KB1XYZ>APMDN0::W1AW-7   :Cross{049');
      // One exact-match message.
      f.stationService.ingestLine('KB1XYZ>APMDN0::W1AW-9   :Exact{050');
      await Future.delayed(const Duration(milliseconds: 50));

      // Thread contains both — should be visible.
      expect(
        f.service.conversations.any((c) => c.peerCallsign == 'KB1XYZ'),
        isTrue,
      );
    });

    test('showOtherSsids true shows cross-SSID-only thread', () async {
      final f = await _Fixture.create(callsign: 'W1AW', ssid: 9);
      await f.service.setShowOtherSsids(true);

      f.stationService.ingestLine('KB1XYZ>APMDN0::W1AW-7   :Hello{051');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(
        f.service.conversations.any((c) => c.peerCallsign == 'KB1XYZ'),
        isTrue,
      );
    });

    test('ACK for wrong SSID is ignored — no conversation mutation', () async {
      final f = await _Fixture.create(callsign: 'W1AW', ssid: 9);

      // Send an outgoing message so W1AW-9 has a pending entry.
      await f.service.sendMessage('KB1XYZ', 'Hi');
      final convBefore = f.service.conversationWith('KB1XYZ')!;
      final statusBefore = convBefore.messages.first.status;

      // Inject ACK addressed to W1AW-7 (wrong SSID).
      f.stationService.ingestLine('KB1XYZ>APMDN0::W1AW-7   :ack001');
      await Future.delayed(const Duration(milliseconds: 50));

      final conv = f.service.conversationWith('KB1XYZ')!;
      expect(conv.messages.first.status, equals(statusBefore));
    });

    test(
      'allConversations exposes cross-SSID thread regardless of showOtherSsids',
      () async {
        final f = await _Fixture.create(callsign: 'W1AW', ssid: 9);
        expect(f.service.showOtherSsids, isFalse);

        f.stationService.ingestLine('KB1XYZ>APMDN0::W1AW-7   :Hello{052');
        await Future.delayed(const Duration(milliseconds: 50));

        // Hidden from conversations.
        expect(
          f.service.conversations.any((c) => c.peerCallsign == 'KB1XYZ'),
          isFalse,
        );
        // But visible in allConversations.
        expect(
          f.service.allConversations.any((c) => c.peerCallsign == 'KB1XYZ'),
          isTrue,
        );
      },
    );
  });

  // --- Legacy addressee=null deserialization ------------------------------

  group('legacy serialization', () {
    test(
      'entry without addressee key deserializes with null, isCrossSsid false',
      () async {
        // Seed SharedPreferences with a persisted conversation whose message
        // has no 'addressee' key (simulating data written before this feature).
        final legacyEntry = {
          'localId': 'KB1XYZ:Hello',
          'wireId': null,
          'text': 'Hello',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'isOutgoing': false,
          'status': 'acked',
          'retryCount': 0,
          // No 'addressee' key.
        };
        final legacyConv = {
          'peer': 'KB1XYZ',
          'unreadCount': 0,
          'lastActivity': DateTime.now().millisecondsSinceEpoch,
          'messages': [legacyEntry],
        };

        SharedPreferences.setMockInitialValues({
          'user_callsign': 'W1AW',
          'user_ssid': 9,
          'message_id_counter': 0,
          'msg_peers': jsonEncode(['KB1XYZ']),
          'msg_conv_KB1XYZ': jsonEncode(legacyConv),
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
        await service.loadHistory();

        final conv = service.conversationWith('KB1XYZ');
        expect(conv, isNotNull);
        final entry = conv!.messages.first;
        expect(entry.addressee, isNull);
        expect(entry.isCrossSsid(service.myFullAddress), isFalse);
      },
    );
  });
}
