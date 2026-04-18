/// Central notification dispatch service for Meridian APRS.
///
/// Subscribes to [MessageService] on the main Dart isolate (which stays alive
/// on both Android via the foreground service and iOS via VoIP mode), detects
/// new inbound messages, and dispatches system notifications and in-app banners.
///
/// See ADR-035 in docs/DECISIONS.md for the main-isolate dispatch rationale.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/notification_preferences.dart';
import '../screens/message_thread_screen.dart';
import '../ui/utils/platform_route.dart';
import '../ui/widgets/in_app_banner_overlay.dart';
import 'message_service.dart';

/// Notification IDs.
///
/// Per-callsign IDs are derived from the callsign hash so repeated messages
/// from the same peer replace the existing notification rather than stacking.
/// The group summary uses a fixed ID so it can be updated in place.
const _kGroupSummaryId = 0;
const _kReplyActionId = 'reply';
const _kMarkReadActionId = 'mark_read';
const _kGroupKey = 'meridian_messages';
const _kReplyOutboxKey = 'notification_reply_outbox';

/// IsolateNameServer port name for routing background replies to the live main
/// isolate (foreground service keeps it alive even when no Activity is visible).
const _kReplyPortName = 'meridian_notification_reply';

/// Top-level handler for background/terminated-app inline reply and mark-read
/// actions.
///
/// When the foreground service is running, the main Dart isolate is alive and
/// has registered [_kReplyPortName] — messages are routed directly via
/// [IsolateNameServer] so they are processed immediately without touching the
/// reply outbox.
///
/// When the app is fully terminated, the outbox path is used instead and the
/// spinner is cleared by cancelling the notification after plugin init.
@pragma('vm:entry-point')
void onNotificationBackgroundResponse(NotificationResponse response) async {
  if (response.notificationResponseType !=
      NotificationResponseType.selectedNotificationAction) {
    return;
  }
  WidgetsFlutterBinding.ensureInitialized();
  final callsign = response.payload ?? '';

  // --- Mark as read ---
  if (response.actionId == _kMarkReadActionId) {
    final mainPort = IsolateNameServer.lookupPortByName(_kReplyPortName);
    if (mainPort != null) {
      mainPort.send({'action': 'mark_read', 'callsign': callsign});
      return;
    }
    // Terminated — just dismiss the notification (no MessageService to call).
    await _cancelNotificationForCallsign(callsign);
    return;
  }

  // --- Inline reply ---
  final input = response.input;
  if (input == null || input.isEmpty) return;

  final mainPort = IsolateNameServer.lookupPortByName(_kReplyPortName);
  if (mainPort != null) {
    // Foreground service is running — route reply directly to main isolate.
    mainPort.send({'action': 'reply', 'callsign': callsign, 'text': input});
    return;
  }

  // Terminated-app fallback: queue in outbox, drain on next foreground resume.
  final prefs = await SharedPreferences.getInstance();
  final outbox = prefs.getStringList(_kReplyOutboxKey) ?? [];
  outbox.add(jsonEncode({'callsign': callsign, 'text': input}));
  await prefs.setStringList(_kReplyOutboxKey, outbox);

  // Dismiss the spinner by cancelling the notification.
  await _cancelNotificationForCallsign(callsign);
}

/// Cancels a per-callsign notification and the group summary.
/// Initialises the plugin minimally when called from a background isolate.
Future<void> _cancelNotificationForCallsign(String callsign) async {
  final notifId = callsign.hashCode.abs() % 100000 + 1;
  try {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await plugin.cancel(notifId);
    await plugin.cancel(_kGroupSummaryId);
  } catch (_) {}
}

class NotificationService extends ChangeNotifier with WidgetsBindingObserver {
  NotificationService({
    required MessageService messageService,
    required SharedPreferences prefs,
    required GlobalKey<NavigatorState> navigatorKey,
    required InAppBannerController bannerController,
  }) : _messageService = messageService,
       _prefs = prefs,
       _navigatorKey = navigatorKey,
       _bannerController = bannerController;

  final MessageService _messageService;
  final SharedPreferences _prefs;
  final GlobalKey<NavigatorState> _navigatorKey;
  final InAppBannerController _bannerController;

  final _plugin = FlutterLocalNotificationsPlugin();

  NotificationPreferences _notifPrefs = NotificationPreferences.defaults();
  NotificationPreferences get preferences => _notifPrefs;

  /// Callsign of the thread currently open in [MessageThreadScreen], if any.
  String? _activeThreadCallsign;

  /// Snapshot of per-callsign unread counts used to detect new messages.
  final _lastUnread = <String, int>{};

  /// Index into [Conversation.messages] at which the current notification
  /// thread started (i.e. the first message that triggered the notification).
  /// Cleared when the user opens the thread via [setActiveThread].
  final _notifStartIndex = <String, int>{};

  /// ReceivePort registered under [_kReplyPortName] so the background handler
  /// can route replies directly to the live main isolate.
  ReceivePort? _replyPort;

  bool _initialized = false;
  bool _androidEnabled = true;
  bool _desktopNotifierReady = false;

  bool get notificationsEnabled =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS)
      ? _androidEnabled
      : true;

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    WidgetsBinding.instance.addObserver(this);
    _notifPrefs = await NotificationPreferences.load(_prefs);

    if (!kIsWeb) {
      if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
        await _initMobileNotifications();
      }
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        await localNotifier.setup(
          appName: 'Meridian APRS',
          shortcutPolicy: ShortcutPolicy.requireCreate,
        );
        _desktopNotifierReady = true;
      }
    }

    _registerReplyPort();
    await _drainReplyOutbox();
    _schedulePostFrameLaunchCheck();

    _messageService.addListener(_onMessageServiceChange);

    // Seed the snapshot so the first notification fires only for genuinely
    // new messages, not for all persisted unread counts on cold start.
    for (final conv in _messageService.conversations) {
      _lastUnread[conv.peerCallsign] = conv.unreadCount;
    }
  }

  void _registerReplyPort() {
    _replyPort = ReceivePort();
    IsolateNameServer.removePortNameMapping(_kReplyPortName);
    IsolateNameServer.registerPortWithName(
      _replyPort!.sendPort,
      _kReplyPortName,
    );
    _replyPort!.listen(_handleIsolateMessage);
  }

  void _handleIsolateMessage(dynamic message) {
    if (message is! Map) return;
    final action = message['action'] as String?;
    final callsign = (message['callsign'] as String?) ?? '';
    if (callsign.isEmpty) return;

    if (action == 'reply') {
      final text = (message['text'] as String?) ?? '';
      if (text.isNotEmpty) {
        _messageService.sendMessage(
          callsign,
          text,
        ); // ignore: unawaited_futures
        _postReplyUpdate(callsign); // ignore: unawaited_futures
      }
    } else if (action == 'mark_read') {
      _messageService.markRead(callsign);
      if (_initialized) {
        final notifId = callsign.hashCode.abs() % 100000 + 1;
        _plugin.cancel(notifId); // ignore: unawaited_futures
        _plugin.cancel(_kGroupSummaryId); // ignore: unawaited_futures
      }
    }
  }

  Future<void> _initMobileNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    final darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        DarwinNotificationCategory(
          NotificationChannels.messages,
          actions: [
            DarwinNotificationAction.plain(_kMarkReadActionId, 'Mark as Read'),
            DarwinNotificationAction.text(
              _kReplyActionId,
              'Reply',
              buttonTitle: 'Send',
              placeholder: 'Your reply',
            ),
          ],
          options: {DarwinNotificationCategoryOption.hiddenPreviewShowTitle},
        ),
        const DarwinNotificationCategory(NotificationChannels.alerts),
        const DarwinNotificationCategory(NotificationChannels.nearby),
        const DarwinNotificationCategory(NotificationChannels.system),
      ],
    );

    final settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          onNotificationBackgroundResponse,
    );

    if (!kIsWeb && Platform.isAndroid) {
      await _registerAndroidChannels();
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      _androidEnabled = await androidPlugin?.areNotificationsEnabled() ?? true;
    }
  }

  Future<void> _registerAndroidChannels() async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin == null) return;

    const channels = [
      AndroidNotificationChannel(
        NotificationChannels.messages,
        'Messages',
        description: 'Incoming APRS messages addressed to you.',
        importance: Importance.defaultImportance,
        playSound: true,
        enableVibration: true,
      ),
      AndroidNotificationChannel(
        NotificationChannels.alerts,
        'Alerts',
        description: 'WX and NWS APRS alerts.',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
      AndroidNotificationChannel(
        NotificationChannels.nearby,
        'Nearby',
        description: 'Activity from stations in your area.',
        importance: Importance.low,
        playSound: false,
        enableVibration: true,
      ),
      AndroidNotificationChannel(
        NotificationChannels.system,
        'System',
        description: 'Connection and TNC status updates.',
        importance: Importance.min,
        playSound: false,
        enableVibration: false,
      ),
    ];

    for (final ch in channels) {
      await androidPlugin.createNotificationChannel(ch);
    }
  }

  // ---------------------------------------------------------------------------
  // Thread tracking (called from MessageThreadScreen)
  // ---------------------------------------------------------------------------

  void setActiveThread(String? callsign) {
    if (callsign != null && _initialized) {
      final notifId = callsign.hashCode.abs() % 100000 + 1;
      _plugin.cancel(notifId); // ignore: unawaited_futures
    }
    _notifStartIndex.remove(callsign?.toUpperCase());
    _activeThreadCallsign = callsign?.toUpperCase();
  }

  // ---------------------------------------------------------------------------
  // Preferences
  // ---------------------------------------------------------------------------

  Future<void> setChannelEnabled(String channelId, bool enabled) async {
    _notifPrefs = _notifPrefs.copyWithChannel(channelId, enabled);
    await _notifPrefs.save(_prefs);
    notifyListeners();
  }

  Future<void> setSoundEnabled(String channelId, bool enabled) async {
    _notifPrefs = _notifPrefs.copyWithSound(channelId, enabled);
    await _notifPrefs.save(_prefs);
    notifyListeners();
  }

  Future<void> setVibrationEnabled(String channelId, bool enabled) async {
    _notifPrefs = _notifPrefs.copyWithVibration(channelId, enabled);
    await _notifPrefs.save(_prefs);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // MessageService listener
  // ---------------------------------------------------------------------------

  void _onMessageServiceChange() {
    final conversations = _messageService.conversations;
    for (final conv in conversations) {
      final peer = conv.peerCallsign;
      final prevUnread = _lastUnread[peer] ?? 0;
      if (conv.unreadCount > prevUnread) {
        // Record the thread anchor on the 0→1+ unread transition so the
        // notification shows only messages from this notification event onward.
        if (prevUnread == 0) {
          final startIdx = (conv.messages.length - conv.unreadCount).clamp(
            0,
            conv.messages.length,
          );
          _notifStartIndex[peer.toUpperCase()] = startIdx;
        }
        final lastMsg = conv.lastMessage;
        if (lastMsg != null && !lastMsg.isOutgoing) {
          _dispatchMessage(peer, lastMsg.text);
        }
      }
      _lastUnread[peer] = conv.unreadCount;
    }
  }

  // ---------------------------------------------------------------------------
  // Dispatch
  // ---------------------------------------------------------------------------

  Future<void> _dispatchMessage(String callsign, String text) async {
    if (!_notifPrefs.isChannelEnabled(NotificationChannels.messages)) return;

    // In-app banner (fires regardless of foreground/background state,
    // but not if the user is already looking at that thread).
    if (_activeThreadCallsign?.toUpperCase() != callsign.toUpperCase()) {
      _bannerController.show(callsign, text);
    }

    if (kIsWeb) return;

    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      await _dispatchMobileNotification(callsign, text);
    } else if (Platform.isWindows || Platform.isLinux) {
      await _dispatchDesktopNotification(callsign, text);
    }
  }

  Future<void> _dispatchMobileNotification(String callsign, String text) async {
    final withSound = _notifPrefs.isSoundEnabled(NotificationChannels.messages);
    final withVibration = _notifPrefs.isVibrationEnabled(
      NotificationChannels.messages,
    );

    final unreadConvs = _messageService.conversations
        .where((c) => c.unreadCount > 0)
        .toList();

    final notifId = callsign.hashCode.abs() % 100000 + 1;

    if (unreadConvs.length >= 3) {
      await _dispatchGroupedNotification(unreadConvs, withSound, withVibration);
    } else {
      await _dispatchSingleNotification(
        notifId,
        callsign,
        text,
        withSound,
        withVibration,
      );
    }
  }

  Future<void> _dispatchSingleNotification(
    int id,
    String callsign,
    String text,
    bool withSound,
    bool withVibration,
  ) async {
    final preview = text.length > 80 ? '${text.substring(0, 80)}…' : text;

    final androidDetails = AndroidNotificationDetails(
      NotificationChannels.messages,
      'Messages',
      channelDescription: 'Incoming APRS messages addressed to you.',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      playSound: withSound,
      enableVibration: withVibration,
      groupKey: _kGroupKey,
      styleInformation: _buildMessagingStyle(callsign),
      actions: [
        const AndroidNotificationAction(
          _kMarkReadActionId,
          'Mark as read',
          showsUserInterface: false,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          _kReplyActionId,
          'Reply',
          inputs: [const AndroidNotificationActionInput(label: 'Your reply')],
          showsUserInterface: false,
          cancelNotification: false,
        ),
      ],
    );

    final darwinDetails = DarwinNotificationDetails(
      categoryIdentifier: NotificationChannels.messages,
      threadIdentifier: callsign,
      presentAlert: true,
      presentSound: withSound,
      presentBadge: true,
    );

    await _plugin.show(
      id,
      callsign,
      preview,
      NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
        macOS: darwinDetails,
      ),
      payload: callsign,
    );
  }

  /// Builds a [MessagingStyleInformation] anchored at the message that first
  /// triggered the notification for this callsign.
  ///
  /// Reads directly from [MessageService] so the thread stays in sync without
  /// a parallel state map. The [Person] for the peer uses only a key (no name
  /// or icon) so Android does not render an avatar bubble.
  MessagingStyleInformation _buildMessagingStyle(String callsign) {
    final conv = _messageService.conversationWith(callsign);
    final all = conv?.messages ?? [];
    final startIdx =
        _notifStartIndex[callsign.toUpperCase()] ??
        (all.length > 10 ? all.length - 10 : 0);
    final slice = startIdx < all.length ? all.sublist(startIdx) : all;

    final peer = Person(key: callsign);
    const me = Person(key: 'me');

    return MessagingStyleInformation(
      me,
      groupConversation: false,
      conversationTitle: callsign,
      messages: slice
          .map((m) => Message(m.text, m.timestamp, m.isOutgoing ? null : peer))
          .toList(),
    );
  }

  /// Re-posts the per-callsign notification after an outgoing reply so the
  /// Android thread stays visible without playing sound or vibrating again.
  Future<void> _postReplyUpdate(String callsign) async {
    if (!_initialized || kIsWeb) return;
    if (!Platform.isAndroid) return;

    final notifId = callsign.hashCode.abs() % 100000 + 1;
    final androidDetails = AndroidNotificationDetails(
      NotificationChannels.messages,
      'Messages',
      channelDescription: 'Incoming APRS messages addressed to you.',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      playSound: false,
      enableVibration: false,
      groupKey: _kGroupKey,
      styleInformation: _buildMessagingStyle(callsign),
      actions: [
        const AndroidNotificationAction(
          _kMarkReadActionId,
          'Mark as read',
          showsUserInterface: false,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          _kReplyActionId,
          'Reply',
          inputs: [const AndroidNotificationActionInput(label: 'Your reply')],
          showsUserInterface: false,
          cancelNotification: false,
        ),
      ],
    );
    await _plugin.show(
      notifId,
      callsign,
      'Message sent',
      NotificationDetails(android: androidDetails),
      payload: callsign,
    );
  }

  Future<void> _dispatchGroupedNotification(
    List<Conversation> unreadConvs,
    bool withSound,
    bool withVibration,
  ) async {
    final total = unreadConvs.fold<int>(0, (s, c) => s + c.unreadCount);
    final lines = unreadConvs.map((c) {
      final preview = c.lastMessage?.text ?? '';
      return '${c.peerCallsign}: ${preview.length > 40 ? '${preview.substring(0, 40)}…' : preview}';
    }).toList();

    final androidDetails = AndroidNotificationDetails(
      NotificationChannels.messages,
      'Messages',
      channelDescription: 'Incoming APRS messages addressed to you.',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      playSound: withSound,
      enableVibration: withVibration,
      groupKey: _kGroupKey,
      setAsGroupSummary: true,
      styleInformation: InboxStyleInformation(
        lines,
        summaryText: '$total new APRS messages',
      ),
    );

    await _plugin.show(
      _kGroupSummaryId,
      'Meridian APRS',
      '$total new messages',
      NotificationDetails(android: androidDetails),
      payload: '',
    );
  }

  Future<void> _dispatchDesktopNotification(
    String callsign,
    String text,
  ) async {
    if (!_desktopNotifierReady) return;
    final preview = text.length > 80 ? '${text.substring(0, 80)}…' : text;
    final notification = LocalNotification(title: callsign, body: preview);
    notification.onClick = () => _navigateToThread(callsign);
    await notification.show();
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  void _navigateToThread(String callsign) {
    final nav = _navigatorKey.currentState;
    if (nav == null) return;
    nav.push(
      buildPlatformRoute((_) => MessageThreadScreen(peerCallsign: callsign)),
    );
  }

  @visibleForTesting
  void handleNotificationResponse(NotificationResponse response) =>
      _onNotificationResponse(response);

  @visibleForTesting
  void handleMessageServiceChange() => _onMessageServiceChange();

  @visibleForTesting
  Future<void> drainReplyOutboxForTest() => _drainReplyOutbox();

  @visibleForTesting
  MessagingStyleInformation buildMessagingStyleForTest(String callsign) =>
      _buildMessagingStyle(callsign);

  void _onNotificationResponse(NotificationResponse response) {
    final callsign = response.payload ?? '';

    if (response.notificationResponseType ==
        NotificationResponseType.selectedNotificationAction) {
      if (response.actionId == _kMarkReadActionId && callsign.isNotEmpty) {
        _messageService.markRead(callsign);
        // cancelNotification: true on the action dismisses the notification
        // automatically; also clear the group summary to be safe.
        if (_initialized) {
          _plugin.cancel(_kGroupSummaryId); // ignore: unawaited_futures
        }
        return;
      }

      if (response.actionId == _kReplyActionId) {
        final input = response.input;
        if (input != null && input.isNotEmpty && callsign.isNotEmpty) {
          _messageService.sendMessage(
            callsign,
            input,
          ); // ignore: unawaited_futures
          _postReplyUpdate(callsign); // ignore: unawaited_futures
        }
        return;
      }

      return;
    }

    // Regular tap — navigate to thread.
    if (callsign.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigateToThread(callsign);
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Cold-start launch details
  // ---------------------------------------------------------------------------

  void _schedulePostFrameLaunchCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (kIsWeb) return;
      if (!Platform.isAndroid && !Platform.isIOS) return;
      try {
        final details = await _plugin.getNotificationAppLaunchDetails();
        if (details == null || !details.didNotificationLaunchApp) return;
        final response = details.notificationResponse;
        if (response != null) _onNotificationResponse(response);
      } catch (_) {}
    });
  }

  // ---------------------------------------------------------------------------
  // Reply outbox (terminated-app inline replies)
  // ---------------------------------------------------------------------------

  Future<void> _drainReplyOutbox() async {
    final outbox = _prefs.getStringList(_kReplyOutboxKey);
    if (outbox == null || outbox.isEmpty) return;
    await _prefs.remove(_kReplyOutboxKey);
    for (final entry in outbox) {
      try {
        final map = jsonDecode(entry) as Map<String, dynamic>;
        final callsign = map['callsign'] as String? ?? '';
        final text = map['text'] as String? ?? '';
        if (callsign.isNotEmpty && text.isNotEmpty) {
          await _messageService.sendMessage(callsign, text);
          await _postReplyUpdate(callsign);
        }
      } catch (e) {
        debugPrint('NotificationService: failed to drain reply: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _drainReplyOutbox(); // ignore: unawaited_futures
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageService.removeListener(_onMessageServiceChange);
    IsolateNameServer.removePortNameMapping(_kReplyPortName);
    _replyPort?.close();
    _replyPort = null;
    super.dispose();
  }
}
