import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meridian_aprs/core/connection/connection_registry.dart';
import 'package:meridian_aprs/models/notification_preferences.dart';
import 'package:meridian_aprs/services/message_service.dart';
import 'package:meridian_aprs/services/notification_service.dart';
import 'package:meridian_aprs/services/station_service.dart';
import 'package:meridian_aprs/services/station_settings_service.dart';
import 'package:meridian_aprs/services/tx_service.dart';
import 'package:meridian_aprs/ui/widgets/in_app_banner_overlay.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final _navigatorKey = GlobalKey<NavigatorState>();

class _Fixture {
  _Fixture._({
    required this.messageService,
    required this.notificationService,
    required this.bannerController,
    required this.stationService,
  });

  final MessageService messageService;
  final NotificationService notificationService;
  final InAppBannerController bannerController;
  final StationService stationService;

  static Future<_Fixture> create({
    String callsign = 'W1AW',
    int ssid = 9,
    Map<String, Object> prefOverrides = const {},
  }) async {
    SharedPreferences.setMockInitialValues({
      'user_callsign': callsign,
      'user_ssid': ssid,
      'message_id_counter': 0,
      ...prefOverrides,
    });

    final prefs = await SharedPreferences.getInstance();
    final settings = StationSettingsService(prefs);
    final stationService = StationService();
    final registry = ConnectionRegistry();
    final txService = _SilentTxService(registry);
    final messageService = MessageService(settings, txService, stationService);
    final bannerController = InAppBannerController();

    // Construct NotificationService WITHOUT calling initialize() so we avoid
    // touching the flutter_local_notifications platform channel in tests.
    final notificationService = NotificationService(
      messageService: messageService,
      prefs: prefs,
      navigatorKey: _navigatorKey,
      bannerController: bannerController,
    );

    // Manually seed preferences (skips the prefs load that initialize() does).
    await NotificationPreferences.defaults().save(prefs);

    // Manually wire the MessageService listener (normally done in initialize()).
    messageService.addListener(notificationService.handleMessageServiceChange);

    return _Fixture._(
      messageService: messageService,
      notificationService: notificationService,
      bannerController: bannerController,
      stationService: stationService,
    );
  }

  void dispose() {
    messageService.removeListener(
      notificationService.handleMessageServiceChange,
    );
    notificationService.dispose();
    messageService.dispose();
  }

  void injectInbound(String from, String text, {String msgId = '042'}) {
    // Build an APRS message line addressed to our callsign (W1AW-9).
    stationService.ingestLine('$from>APZMDN::W1AW-9   :$text{$msgId');
  }
}

/// TxService that silently drops outgoing traffic (no real transport).
class _SilentTxService extends TxService {
  _SilentTxService(super.registry);

  @override
  Future<void> sendLine(String line, {ConnectionType? forceVia}) async {}
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationService — banner dispatch', () {
    late _Fixture f;

    setUp(() async {
      f = await _Fixture.create();
    });

    tearDown(() => f.dispose());

    test(
      'inbound message shows banner when messages channel is enabled',
      () async {
        f.injectInbound('WB5XYZ', 'Hello there');
        await Future.delayed(const Duration(milliseconds: 50));

        expect(f.bannerController.current, isNotNull);
        expect(f.bannerController.current!.callsign, 'WB5XYZ');
        expect(f.bannerController.current!.text, 'Hello there');
      },
    );

    test('banner is suppressed when messages channel is disabled', () async {
      await f.notificationService.setChannelEnabled(
        NotificationChannels.messages,
        false,
      );

      f.injectInbound('WB5XYZ', 'Hello');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(f.bannerController.current, isNull);
    });

    test('banner is suppressed when that callsign thread is active', () async {
      f.notificationService.setActiveThread('WB5XYZ');

      f.injectInbound('WB5XYZ', 'Hello');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(f.bannerController.current, isNull);
    });

    test(
      'banner shows when different callsign arrives than active thread',
      () async {
        f.notificationService.setActiveThread('WB5XYZ');

        f.injectInbound('K6ABC', 'Hey', msgId: '099');
        await Future.delayed(const Duration(milliseconds: 50));

        expect(f.bannerController.current, isNotNull);
        expect(f.bannerController.current!.callsign, 'K6ABC');
      },
    );

    test('duplicate message does not trigger a second banner', () async {
      f.injectInbound('WB5XYZ', 'Hello', msgId: '001');
      await Future.delayed(const Duration(milliseconds: 50));
      f.bannerController.dismiss();

      // Same ID → duplicate, MessageService dedupes it.
      f.injectInbound('WB5XYZ', 'Hello', msgId: '001');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(f.bannerController.current, isNull);
    });
  });

  group('NotificationService — MessagingStyle builder', () {
    late _Fixture f;

    setUp(() async {
      f = await _Fixture.create();
    });

    tearDown(() => f.dispose());

    test('messages appear in order with correct sender mapping', () async {
      f.injectInbound('WB5XYZ', 'Hello', msgId: '001');
      await Future.delayed(const Duration(milliseconds: 50));
      await f.messageService.sendMessage('WB5XYZ', 'Hi back');

      final style = f.notificationService.buildMessagingStyleForTest('WB5XYZ');
      expect(style.messages, hasLength(2));
      // Inbound: person key = peer callsign (no name = no avatar bubble)
      expect(style.messages!.first.text, 'Hello');
      expect(style.messages!.first.person?.name, 'WB5XYZ');
      // Outgoing: person = null (sent by "You")
      expect(style.messages!.last.text, 'Hi back');
      expect(style.messages!.last.person, isNull);
    });

    test('builder returns empty messages for unknown callsign', () {
      final style = f.notificationService.buildMessagingStyleForTest(
        'K0UNKNOWN',
      );
      expect(style.messages ?? [], isEmpty);
    });
  });

  group('NotificationService — inline reply routing', () {
    late _Fixture f;

    setUp(() async {
      f = await _Fixture.create();
    });

    tearDown(() => f.dispose());

    test('reply action sends message to correct callsign', () async {
      const response = NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        actionId: 'reply',
        input: 'This is my reply',
        payload: 'WB5XYZ',
        id: 1,
      );

      f.notificationService.handleNotificationResponse(response);
      await Future.delayed(const Duration(milliseconds: 50));

      final conv = f.messageService.conversationWith('WB5XYZ');
      expect(conv, isNotNull);
      final outgoing = conv!.messages.where((m) => m.isOutgoing).toList();
      expect(outgoing, hasLength(1));
      expect(outgoing.first.text, 'This is my reply');
    });

    test('reply with empty input is silently ignored', () async {
      const response = NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        actionId: 'reply',
        input: '',
        payload: 'WB5XYZ',
        id: 1,
      );

      f.notificationService.handleNotificationResponse(response);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(f.messageService.conversations, isEmpty);
    });

    test('reply with empty payload is silently ignored', () async {
      const response = NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        actionId: 'reply',
        input: 'Hello',
        payload: '',
        id: 1,
      );

      f.notificationService.handleNotificationResponse(response);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(f.messageService.conversations, isEmpty);
    });
  });

  group('NotificationService — terminated-app reply outbox', () {
    test('pending replies are drained and sent on initialize', () async {
      SharedPreferences.setMockInitialValues({
        'user_callsign': 'W1AW',
        'user_ssid': 9,
        'message_id_counter': 0,
        'notification_reply_outbox': [
          '{"callsign":"WB5XYZ","text":"Pending reply"}',
          '{"callsign":"K6ABC","text":"Another reply"}',
        ],
      });

      final prefs = await SharedPreferences.getInstance();
      final settings = StationSettingsService(prefs);
      final stationService = StationService();
      final registry = ConnectionRegistry();
      final txService = _SilentTxService(registry);
      final messageService = MessageService(
        settings,
        txService,
        stationService,
      );
      final bannerController = InAppBannerController();
      final notificationService = NotificationService(
        messageService: messageService,
        prefs: prefs,
        navigatorKey: _navigatorKey,
        bannerController: bannerController,
      );

      await notificationService.drainReplyOutboxForTest();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(messageService.conversationWith('WB5XYZ'), isNotNull);
      expect(messageService.conversationWith('K6ABC'), isNotNull);

      // Outbox is cleared after drain.
      expect(prefs.getStringList('notification_reply_outbox'), isNull);

      notificationService.dispose();
      messageService.dispose();
    });
  });
}
