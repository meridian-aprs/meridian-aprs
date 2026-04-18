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

/// Top-level handler for background/terminated-app inline reply and mark-read
/// actions.
///
/// flutter_local_notifications spawns the background handler in a fresh
/// FlutterEngine, so cross-isolate mechanisms like IsolateNameServer do not
/// see the main isolate's registered ports. The reliable path is: queue the
/// reply in SharedPreferences, let the main isolate drain it on resume (or on
/// the next cold start via [NotificationService.initialize]).
///
/// The Reply action uses [cancelNotification: true] so Android auto-dismisses
/// the notification (and its RemoteInput spinner) the moment the user taps
/// Send — no explicit cancel needed here.
@pragma('vm:entry-point')
void onNotificationBackgroundResponse(NotificationResponse response) async {
  if (response.notificationResponseType !=
      NotificationResponseType.selectedNotificationAction) {
    return;
  }
  if (response.actionId != _kReplyActionId) return;

  final input = response.input;
  final callsign = response.payload ?? '';
  if (input == null || input.isEmpty || callsign.isEmpty) return;

  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final outbox = prefs.getStringList(_kReplyOutboxKey) ?? [];
  outbox.add(jsonEncode({'callsign': callsign, 'text': input}));
  await prefs.setStringList(_kReplyOutboxKey, outbox);
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

    await _drainReplyOutbox();
    _schedulePostFrameLaunchCheck();

    _messageService.addListener(_onMessageServiceChange);

    // Seed the snapshot so the first notification fires only for genuinely
    // new messages, not for all persisted unread counts on cold start.
    for (final conv in _messageService.conversations) {
      _lastUnread[conv.peerCallsign] = conv.unreadCount;
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

    final notifId = callsign.hashCode.abs() % 100000 + 1;

    // Always post/update the per-callsign notification so the new-message
    // heads-up alert fires regardless of how many other conversations are
    // unread. Replacing an existing notification by the same ID still triggers
    // heads-up on Android when there is new content.
    await _dispatchSingleNotification(
      notifId,
      callsign,
      text,
      withSound,
      withVibration,
    );

    // When multiple conversations are unread, also post a silent group summary
    // so Android groups them in the shade — matching the Google Messages model
    // of one summary + N individual conversation notifications.
    final unreadConvs = _messageService.conversations
        .where((c) => c.unreadCount > 0)
        .toList();
    if (unreadConvs.length >= 2) {
      await _dispatchGroupSummary(unreadConvs);
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
      styleInformation: BigTextStyleInformation(preview),
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
          cancelNotification: true,
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

  /// Posts a silent Android group summary so the notification shade groups all
  /// per-callsign notifications together. Does not play sound or vibrate —
  /// the per-callsign notification already alerted the user.
  Future<void> _dispatchGroupSummary(List<Conversation> unreadConvs) async {
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
      playSound: false,
      enableVibration: false,
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
    // Reload is required: the background handler (separate isolate/engine)
    // writes to disk, but _prefs holds a stale in-memory cache until reloaded.
    await _prefs.reload();
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
    super.dispose();
  }
}
