/// Central notification dispatch service for Meridian APRS.
///
/// Subscribes to [MessageService] on the main Dart isolate (which stays alive
/// on both Android via the foreground service and iOS via VoIP mode), detects
/// new inbound messages, and dispatches system notifications and in-app banners.
///
/// See ADR-035 in docs/DECISIONS.md for the main-isolate dispatch rationale.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:permission_handler/permission_handler.dart';
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

// MethodChannel shared with MainActivity and MeridianNotificationActionReceiver.
// Used for bidirectional Android notification coordination:
//   Dart  → native: postMessageNotification, getPendingNavigation
//   native → Dart:  handleReply, handleMarkRead, navigateToThread
const _kNativeChannel = MethodChannel('meridian/notifications');

class NotificationService extends ChangeNotifier {
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

  /// Per-callsign index into the messages list marking where the current
  /// notification session started. Only messages at or after this index are
  /// shown in the notification. Reset when the notification is dismissed,
  /// mark-as-read, or the thread is opened.
  final _notifAnchor = <String, int>{};

  bool _initialized = false;
  bool _androidEnabled = true;
  bool _desktopNotifierReady = false;

  bool get notificationsEnabled =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS)
      ? _androidEnabled
      : true;

  bool get optedIn => _notifPrefs.optedIn;

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _notifPrefs = await NotificationPreferences.load(_prefs);

    // Migration: pre-v0.12 users had no opt-in concept — if the key is absent
    // and the OS permission was already granted, preserve their existing
    // behaviour by treating them as opted in.
    if (!_prefs.containsKey('notif_opted_in') &&
        !kIsWeb &&
        Platform.isAndroid) {
      final status = await Permission.notification.status;
      if (status.isGranted) {
        _notifPrefs = _notifPrefs.copyWithOptedIn(true);
        await _notifPrefs.save(_prefs);
      }
    }

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

      // Android-specific: register the native MethodChannel handler and check
      // for a pending navigation from a cold-start notification tap.
      if (Platform.isAndroid) {
        _kNativeChannel.setMethodCallHandler(_handleNativeCall);
        _schedulePendingNavCheck();
      }
    }

    _schedulePostFrameLaunchCheck();

    _messageService.addListener(_onMessageServiceChange);

    // Seed the snapshot so the first notification fires only for genuinely
    // new messages, not for all persisted unread counts on cold start.
    // Use allConversations (not conversations) so cross-SSID threads are
    // seeded even when showOtherSsids is false — prevents spurious re-notify
    // of pre-existing cross-SSID unread counts on startup.
    for (final conv in _messageService.allConversations) {
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
    ];

    for (final ch in channels) {
      await androidPlugin.createNotificationChannel(ch);
    }

    // Remove pre-v0.12 channels that were registered but never dispatched.
    // Safe on fresh installs — deleteNotificationChannel is a no-op if absent.
    for (final stale in const ['alerts', 'nearby', 'system']) {
      await androidPlugin.deleteNotificationChannel(stale);
    }
  }

  // ---------------------------------------------------------------------------
  // Android native channel handler
  // ---------------------------------------------------------------------------

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'handleReply':
        final callsign = call.arguments['callsign'] as String;
        final text = call.arguments['text'] as String;
        final notifId = call.arguments['notificationId'] as int;
        await _messageService.sendMessage(callsign, text);
        // Re-post with alertOnce:true so the spinner clears without heads-up.
        await _dispatchAndroidNotification(
          notifId,
          callsign,
          _notifPrefs.isSoundEnabled(NotificationChannels.messages),
          alertOnce: true,
        );

      case 'handleMarkRead':
        final callsign = call.arguments['callsign'] as String;
        _messageService.markRead(callsign);
        _notifAnchor.remove(callsign);
        // Cancel group summary if fewer than 2 conversations remain unread.
        final remaining = _messageService.conversations
            .where((c) => c.unreadCount > 0)
            .length;
        if (remaining < 2 && _initialized) {
          _plugin
              .cancel(_kGroupSummaryId)
              .catchError((_) {}); // ignore: unawaited_futures
        }

      case 'handleDismissed':
        final callsign = call.arguments['callsign'] as String;
        _notifAnchor.remove(callsign);

      case 'navigateToThread':
        final callsign = call.arguments['callsign'] as String;
        if (callsign.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _navigateToThread(callsign);
          });
        }
    }
  }

  /// Checks for a pending notification-tap navigation from a cold start.
  /// MainActivity holds the callsign until Dart calls `getPendingNavigation`.
  void _schedulePendingNavCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final callsign = await _kNativeChannel.invokeMethod<String>(
          'getPendingNavigation',
        );
        if (callsign != null && callsign.isNotEmpty) {
          _navigateToThread(callsign);
        }
      } catch (_) {}
    });
  }

  // ---------------------------------------------------------------------------
  // Thread tracking (called from MessageThreadScreen)
  // ---------------------------------------------------------------------------

  void setActiveThread(String? callsign) {
    if (callsign != null && _initialized) {
      final notifId = callsign.hashCode.abs() % 100000 + 1;
      _plugin.cancel(notifId).catchError((_) {}); // ignore: unawaited_futures
      _notifAnchor.remove(callsign);
    }
    _activeThreadCallsign = callsign?.toUpperCase();
  }

  // ---------------------------------------------------------------------------
  // Permission request (called from onboarding)
  // ---------------------------------------------------------------------------

  /// Requests the OS-level notification permission and returns whether it was
  /// granted. Safe to call on any platform — returns `true` immediately on
  /// Linux/Windows where no runtime permission is required.
  Future<bool> requestNotificationPermissions() async {
    if (kIsWeb) return false;
    if (Platform.isAndroid) {
      final status = await Permission.notification.request();
      _androidEnabled = status.isGranted;
      if (status.isGranted) await setOptedIn(true);
      notifyListeners();
      return status.isGranted;
    }
    if (Platform.isIOS) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      if (granted == true) await setOptedIn(true);
      return granted ?? false;
    }
    if (Platform.isMacOS) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      if (granted == true) await setOptedIn(true);
      return granted ?? false;
    }
    // Linux/Windows — no runtime permission required; treat as opted in.
    await setOptedIn(true);
    return true;
  }

  // ---------------------------------------------------------------------------
  // Preferences
  // ---------------------------------------------------------------------------

  Future<void> setOptedIn(bool value) async {
    _notifPrefs = _notifPrefs.copyWithOptedIn(value);
    await _notifPrefs.save(_prefs);
    notifyListeners();
  }

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

  Future<void> setNotifyOtherSsids(bool v) async {
    _notifPrefs = _notifPrefs.copyWithNotifyOtherSsids(v);
    await _notifPrefs.save(_prefs);
    notifyListeners();
  }

  Future<void> setNotifyGroups(bool v) async {
    _notifPrefs = _notifPrefs.copyWithNotifyGroups(v);
    await _notifPrefs.save(_prefs);
    notifyListeners();
  }

  Future<void> setNotifyBulletins(bool v) async {
    _notifPrefs = _notifPrefs.copyWithNotifyBulletins(v);
    await _notifPrefs.save(_prefs);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // MessageService listener
  // ---------------------------------------------------------------------------

  void _onMessageServiceChange() {
    final myAddr = _messageService.myFullAddress;
    for (final conv in _messageService.allConversations) {
      final peer = conv.peerCallsign;
      final prevUnread = _lastUnread[peer] ?? 0;
      if (conv.unreadCount > prevUnread) {
        final lastMsg = conv.lastMessage;
        if (lastMsg != null && !lastMsg.isOutgoing) {
          final isCross = lastMsg.isCrossSsid(myAddr);
          if (isCross) {
            if (_notifPrefs.notifyOtherSsids) {
              _dispatchMessage(
                peer,
                lastMsg.text,
                crossSsidAddressee: lastMsg.addressee,
              );
            }
          } else {
            _dispatchMessage(peer, lastMsg.text);
          }
        }
      }
      _lastUnread[peer] = conv.unreadCount;
    }
  }

  // ---------------------------------------------------------------------------
  // Dispatch
  // ---------------------------------------------------------------------------

  Future<void> _dispatchMessage(
    String callsign,
    String text, {
    String? crossSsidAddressee,
  }) async {
    if (!_notifPrefs.optedIn) return;
    if (!_notifPrefs.isChannelEnabled(NotificationChannels.messages)) return;

    // Build a display label for cross-SSID messages: "W1ABC-9 → your -7".
    // For exact-match messages the callsign is used unchanged.
    final displayTitle = crossSsidAddressee != null
        ? '$callsign → your ${_ssidSuffix(crossSsidAddressee)}'
        : callsign;

    // In-app banner (fires regardless of foreground/background state,
    // but not if the user is already looking at that thread).
    if (_activeThreadCallsign?.toUpperCase() != callsign.toUpperCase()) {
      _bannerController.show(displayTitle, text);
    }

    if (kIsWeb) return;

    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      await _dispatchMobileNotification(
        callsign,
        text,
        displayTitle: displayTitle,
      );
    } else if (Platform.isWindows || Platform.isLinux) {
      await _dispatchDesktopNotification(
        callsign,
        text,
        displayTitle: displayTitle,
      );
    }
  }

  /// Extracts the SSID suffix from a full callsign string for use in
  /// cross-SSID notification titles.
  ///
  /// 'KM4TJO-7' returns '-7'.
  /// 'KM4TJO' (no SSID) returns '' — no suffix to display.
  String _ssidSuffix(String callsign) {
    final upper = callsign.trim().toUpperCase();
    final dashIdx = upper.lastIndexOf('-');
    return dashIdx == -1 ? '' : upper.substring(dashIdx);
  }

  Future<void> _dispatchMobileNotification(
    String callsign,
    String text, {
    String? displayTitle,
  }) async {
    final withSound = _notifPrefs.isSoundEnabled(NotificationChannels.messages);
    final withVibration = _notifPrefs.isVibrationEnabled(
      NotificationChannels.messages,
    );
    final notifId = callsign.hashCode.abs() % 100000 + 1;
    final titleToUse = displayTitle ?? callsign;

    if (!kIsWeb && Platform.isAndroid) {
      // Android: post natively so inline reply works without opening the app.
      // The callsign (not titleToUse) is passed for routing — native reply
      // actions key on callsign. displayTitle is forwarded so the native side
      // can use it for the visible title once it reads the new key.
      await _dispatchAndroidNotification(
        notifId,
        callsign,
        withSound,
        displayTitle: titleToUse,
      );

      // Group summary for 2+ unread conversations.
      final unreadConvs = _messageService.allConversations
          .where((c) => c.unreadCount > 0)
          .toList();
      if (unreadConvs.length >= 2) {
        await _dispatchGroupSummary(unreadConvs);
      }
    } else {
      // iOS / macOS: use flutter_local_notifications.
      await _dispatchSingleNotification(
        notifId,
        callsign,
        text,
        withSound,
        withVibration,
        displayTitle: titleToUse,
      );
    }
  }

  /// Posts an Android notification natively via [MainActivity] so that the
  /// custom [MeridianNotificationActionReceiver] PendingIntents are used for
  /// inline reply and mark-as-read — enabling reply without opening the app.
  ///
  /// [displayTitle] is forwarded to native for the visible notification title.
  /// Routing (reply / mark-as-read) always uses [callsign] — never displayTitle.
  /// NOTE: native Kotlin must read `displayTitle` from the arg map to use it;
  /// until that follow-up lands, Android will continue showing the plain callsign.
  Future<void> _dispatchAndroidNotification(
    int id,
    String callsign,
    bool withSound, {
    bool alertOnce = false,
    String? displayTitle,
  }) async {
    final conv = _messageService.conversationWith(callsign);
    final all = conv?.messages ?? [];

    // Set the anchor to the triggering message on the first dispatch, then
    // keep it so subsequent messages accumulate while the notification is open.
    // Cleared on dismiss, mark-as-read, or thread open — so the next message
    // always starts a fresh notification with no pre-dismissal history.
    if (!_notifAnchor.containsKey(callsign) && all.isNotEmpty) {
      _notifAnchor[callsign] = all.length - 1;
    }
    final anchor = _notifAnchor[callsign] ?? (all.isEmpty ? 0 : all.length - 1);
    final fromAnchor = anchor < all.length
        ? all.sublist(anchor)
        : (all.isNotEmpty ? [all.last] : []);
    final recent = fromAnchor.length > 6
        ? fromAnchor.sublist(fromAnchor.length - 6)
        : fromAnchor;

    final messages = recent.map((m) {
      final body = m.text.length > 80 ? '${m.text.substring(0, 80)}…' : m.text;
      return <String, Object?>{
        'sender': m.isOutgoing ? null : callsign,
        'text': body,
        'timestampMs': m.timestamp.millisecondsSinceEpoch,
      };
    }).toList();

    try {
      await _kNativeChannel.invokeMethod<void>('postMessageNotification', {
        'callsign': callsign,
        'notificationId': id,
        'messages': messages,
        'withSound': withSound,
        'alertOnce': alertOnce,
        // displayTitle: used by native side for the visible notification title.
        // Routing (reply/mark-as-read) always uses 'callsign', not this value.
        if (displayTitle != null && displayTitle != callsign)
          'displayTitle': displayTitle,
      });
    } catch (_) {}
  }

  Future<void> _dispatchSingleNotification(
    int id,
    String callsign,
    String text,
    bool withSound,
    bool withVibration, {
    String? displayTitle,
  }) async {
    // iOS / macOS only — Android uses _dispatchAndroidNotification.
    final darwinDetails = DarwinNotificationDetails(
      categoryIdentifier: NotificationChannels.messages,
      // threadIdentifier groups notifications by conversation; always keyed
      // by raw callsign so threading is correct regardless of display title.
      threadIdentifier: callsign,
      presentAlert: true,
      presentSound: withSound,
      presentBadge: true,
    );

    final preview = text.length > 80 ? '${text.substring(0, 80)}…' : text;
    await _plugin.show(
      id,
      displayTitle ?? callsign,
      preview,
      NotificationDetails(iOS: darwinDetails, macOS: darwinDetails),
      // payload always carries the raw callsign for navigation routing.
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
    String text, {
    String? displayTitle,
  }) async {
    if (!_desktopNotifierReady) return;
    final preview = text.length > 80 ? '${text.substring(0, 80)}…' : text;
    final notification = LocalNotification(
      title: displayTitle ?? callsign,
      body: preview,
    );
    // onClick navigation always routes to the raw callsign thread.
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
  Future<dynamic> handleNativeCallForTest(MethodCall call) =>
      _handleNativeCall(call);

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
  // Cold-start launch details (iOS / macOS via FLN)
  // ---------------------------------------------------------------------------

  void _schedulePostFrameLaunchCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Android uses _schedulePendingNavCheck (pull model via MainActivity).
      // All other platforms and web don't need this check.
      if (kIsWeb || !Platform.isIOS) return;
      try {
        final details = await _plugin.getNotificationAppLaunchDetails();
        if (details == null || !details.didNotificationLaunchApp) return;
        final response = details.notificationResponse;
        if (response != null) _onNotificationResponse(response);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _messageService.removeListener(_onMessageServiceChange);
    super.dispose();
  }
}
