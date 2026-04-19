import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    final txService = _SilentTxService(registry, settings);
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
  _SilentTxService(super.registry, super.settings);

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

  group('NotificationService — Android MethodChannel reply', () {
    late _Fixture f;

    setUp(() async {
      f = await _Fixture.create();
    });

    tearDown(() => f.dispose());

    test('handleReply sends message to correct callsign', () async {
      await f.notificationService.handleNativeCallForTest(
        const MethodCall('handleReply', {
          'callsign': 'WB5XYZ',
          'text': 'Android inline reply',
          'notificationId': 42,
        }),
      );
      await Future.delayed(const Duration(milliseconds: 50));

      final conv = f.messageService.conversationWith('WB5XYZ');
      expect(conv, isNotNull);
      final outgoing = conv!.messages.where((m) => m.isOutgoing).toList();
      expect(outgoing, hasLength(1));
      expect(outgoing.first.text, 'Android inline reply');
    });

    test('handleMarkRead marks conversation as read', () async {
      // Inject an inbound message so there is an unread conversation.
      f.injectInbound('WB5XYZ', 'Are you there?');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(f.messageService.conversationWith('WB5XYZ')?.unreadCount, 1);

      await f.notificationService.handleNativeCallForTest(
        const MethodCall('handleMarkRead', {'callsign': 'WB5XYZ'}),
      );
      await Future.delayed(const Duration(milliseconds: 50));

      expect(f.messageService.conversationWith('WB5XYZ')?.unreadCount, 0);
    });

    test('navigateToThread is handled without throwing', () async {
      // Navigation requires a real navigator; just verify no exception thrown.
      await expectLater(
        f.notificationService.handleNativeCallForTest(
          const MethodCall('navigateToThread', {'callsign': 'WB5XYZ'}),
        ),
        completes,
      );
    });
  });
}
