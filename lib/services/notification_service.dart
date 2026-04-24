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

import '../models/bulletin.dart';
import '../models/group_subscription.dart';
import '../models/notification_preferences.dart';
import '../screens/message_thread_screen.dart';
import '../ui/utils/platform_route.dart';
import '../ui/widgets/in_app_banner_overlay.dart';
import 'bulletin_service.dart';
import 'group_subscription_service.dart';
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
    BulletinService? bulletinService,
    GroupSubscriptionService? groupSubscriptions,
  }) : _messageService = messageService,
       _prefs = prefs,
       _navigatorKey = navigatorKey,
       _bannerController = bannerController,
       _bulletinService = bulletinService,
       _groupSubscriptions = groupSubscriptions;

  final MessageService _messageService;
  final SharedPreferences _prefs;
  final GlobalKey<NavigatorState> _navigatorKey;
  final InAppBannerController _bannerController;
  final BulletinService? _bulletinService;
  final GroupSubscriptionService? _groupSubscriptions;

  final _plugin = FlutterLocalNotificationsPlugin();

  NotificationPreferences _notifPrefs = NotificationPreferences.defaults();
  NotificationPreferences get preferences => _notifPrefs;

  /// Callsign of the thread currently open in [MessageThreadScreen], if any.
  String? _activeThreadCallsign;

  /// Snapshot of per-callsign unread counts used to detect new messages.
  final _lastUnread = <String, int>{};

  /// Snapshot of per-group-key unread counts used to detect new group
  /// messages (v0.17). Keyed by the `#GROUP:<NAME>` conversation key.
  final _lastGroupUnread = <String, int>{};

  /// Snapshot of "bulletin-key → lastHeardAt" used to detect new / retx'd
  /// bulletins (v0.17). We fire a notification when lastHeardAt advances.
  final _lastBulletinKey = <String, DateTime>{};

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

    // Seed group-conversation snapshot the same way.
    for (final conv in _messageService.groupConversations) {
      _lastGroupUnread[conv.peerCallsign] = conv.unreadCount;
    }

    // v0.17: bulletin receive-side dispatch.
    final bs = _bulletinService;
    if (bs != null) {
      for (final b in bs.bulletins) {
        _lastBulletinKey[_bulletinKey(b)] = b.lastHeardAt;
      }
      bs.addListener(_onBulletinServiceChange);
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

    // Channel set per v0.17 ADR-058 §9. Built-in groups and general
    // bulletins use LOW importance (visible but silent by default); custom
    // groups and subscribed bulletin groups use DEFAULT importance to match
    // user intent (explicit subscribe = "tell me"). The bulletin-expired
    // channel is DEFAULT so the "repost?" prompt isn't easy to miss.
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
        NotificationChannels.groupsBuiltin,
        'Built-in groups (CQ, QST, ALL)',
        description: 'Messages to the built-in APRS groups.',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
      ),
      AndroidNotificationChannel(
        NotificationChannels.groupsCustom,
        'Custom groups',
        description: 'Messages to your custom groups (clubs, nets).',
        importance: Importance.defaultImportance,
        playSound: true,
        enableVibration: true,
      ),
      AndroidNotificationChannel(
        NotificationChannels.bulletinsGeneral,
        'General bulletins',
        description: 'General APRS bulletins (BLN0–BLN9).',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
      ),
      AndroidNotificationChannel(
        NotificationChannels.bulletinsSubscribed,
        'Subscribed bulletin groups',
        description: 'Bulletins from groups you subscribe to (e.g. WX).',
        importance: Importance.defaultImportance,
        playSound: true,
        enableVibration: true,
      ),
      AndroidNotificationChannel(
        NotificationChannels.bulletinExpired,
        'Bulletin expired',
        description: 'Your outgoing bulletins have expired — repost?',
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

    // Group conversations — separate unread table so "Other SSID" toggles
    // never suppress a group notification, and vice versa.
    for (final conv in _messageService.groupConversations) {
      final key = conv.peerCallsign;
      final prevUnread = _lastGroupUnread[key] ?? 0;
      if (conv.unreadCount > prevUnread) {
        final lastMsg = conv.lastMessage;
        if (lastMsg != null && !lastMsg.isOutgoing) {
          _dispatchGroupMessage(conv, lastMsg);
        }
      }
      _lastGroupUnread[key] = conv.unreadCount;
    }
  }

  void _onBulletinServiceChange() {
    final bs = _bulletinService;
    if (bs == null) return;
    for (final b in bs.bulletins) {
      final key = _bulletinKey(b);
      final prev = _lastBulletinKey[key];
      // Fire on first receipt OR when lastHeardAt advances AND heardCount
      // == 1 (first appearance; retransmissions bump lastHeardAt but the
      // body is unchanged — no re-notify). If the body changes, ingest
      // re-marks as unread and heardCount keeps climbing; re-notify anyway
      // so the operator sees the edit.
      final isFresh = prev == null;
      if (isFresh) _dispatchBulletin(b);
      _lastBulletinKey[key] = b.lastHeardAt;
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

  // ---------------------------------------------------------------------------
  // Group & bulletin dispatch (v0.17)
  // ---------------------------------------------------------------------------

  Future<void> _dispatchGroupMessage(
    Conversation conv,
    MessageEntry msg,
  ) async {
    if (!_notifPrefs.optedIn) return;
    if (!_notifPrefs.notifyGroups) return;

    // Resolve the bare group name from `#GROUP:<NAME>` key and look up the
    // subscription so per-group `notify` + `isBuiltin` gate correctly.
    final groupName = MessageService.groupNameOf(conv.peerCallsign);
    if (groupName == null) return;

    GroupSubscription? sub;
    for (final s in _groupSubscriptions?.subscriptions ?? const []) {
      if (s.name == groupName) {
        sub = s;
        break;
      }
    }
    if (sub != null && !sub.notify) return;

    final channel = (sub?.isBuiltin ?? false)
        ? NotificationChannels.groupsBuiltin
        : NotificationChannels.groupsCustom;
    if (!_notifPrefs.isChannelEnabled(channel)) return;

    final senderCallsign = msg.fromCallsign ?? '';
    final title = senderCallsign.isEmpty
        ? groupName
        : '$groupName · $senderCallsign';
    _bannerController.show(title, msg.text);
    await _dispatchSimpleNotification(
      id: 'group:$groupName'.hashCode.abs() % 100000 + 2000,
      title: title,
      body: msg.text,
      channelId: channel,
      payloadCallsign: senderCallsign,
    );
  }

  Future<void> _dispatchBulletin(Bulletin b) async {
    if (!_notifPrefs.optedIn) return;
    if (!_notifPrefs.notifyBulletins) return;

    // Named-group bulletins always route to the Subscribed channel (they
    // only land in the store at all if the user opted in via subscription).
    final channel = b.category == BulletinCategory.groupNamed
        ? NotificationChannels.bulletinsSubscribed
        : NotificationChannels.bulletinsGeneral;
    if (!_notifPrefs.isChannelEnabled(channel)) return;

    final title = '${b.addressee} · ${b.sourceCallsign}';
    _bannerController.show(title, b.body);
    await _dispatchSimpleNotification(
      id:
          'bulletin:${b.sourceCallsign}|${b.addressee}'.hashCode.abs() %
              100000 +
          3000,
      title: title,
      body: b.body,
      channelId: channel,
      payloadCallsign: b.sourceCallsign,
    );
  }

  /// Low-ceremony dispatch for group/bulletin notifications. Mirrors the
  /// mobile/desktop split used by [_dispatchMessage] but without the Android
  /// native-reply path (groups + bulletins have no reply affordance in the
  /// notification itself — tap opens the relevant screen).
  Future<void> _dispatchSimpleNotification({
    required int id,
    required String title,
    required String body,
    required String channelId,
    required String payloadCallsign,
  }) async {
    if (kIsWeb) return;
    final withSound = _notifPrefs.isSoundEnabled(channelId);
    final withVibration = _notifPrefs.isVibrationEnabled(channelId);
    final preview = body.length > 80 ? '${body.substring(0, 80)}…' : body;

    if (Platform.isAndroid) {
      final importance = _importanceFor(channelId);
      final androidDetails = AndroidNotificationDetails(
        channelId,
        _channelName(channelId),
        importance: importance,
        priority: importance == Importance.low
            ? Priority.low
            : Priority.defaultPriority,
        playSound: withSound,
        enableVibration: withVibration,
      );
      await _plugin.show(
        id,
        title,
        preview,
        NotificationDetails(android: androidDetails),
        payload: payloadCallsign,
      );
    } else if (Platform.isIOS || Platform.isMacOS) {
      final darwinDetails = DarwinNotificationDetails(
        categoryIdentifier: channelId,
        presentAlert: true,
        presentSound: withSound,
        presentBadge: true,
      );
      await _plugin.show(
        id,
        title,
        preview,
        NotificationDetails(iOS: darwinDetails, macOS: darwinDetails),
        payload: payloadCallsign,
      );
    } else if (Platform.isLinux || Platform.isWindows) {
      if (!_desktopNotifierReady) return;
      final n = LocalNotification(title: title, body: preview);
      await n.show();
    }
  }

  Importance _importanceFor(String channelId) {
    switch (channelId) {
      case NotificationChannels.groupsBuiltin:
      case NotificationChannels.bulletinsGeneral:
        return Importance.low;
      default:
        return Importance.defaultImportance;
    }
  }

  String _channelName(String channelId) {
    switch (channelId) {
      case NotificationChannels.messages:
        return 'Messages';
      case NotificationChannels.groupsBuiltin:
        return 'Built-in groups';
      case NotificationChannels.groupsCustom:
        return 'Custom groups';
      case NotificationChannels.bulletinsGeneral:
        return 'General bulletins';
      case NotificationChannels.bulletinsSubscribed:
        return 'Subscribed bulletin groups';
      case NotificationChannels.bulletinExpired:
        return 'Bulletin expired';
      default:
        return channelId;
    }
  }

  String _bulletinKey(Bulletin b) => '${b.sourceCallsign}|${b.addressee}';

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
    _bulletinService?.removeListener(_onBulletinServiceChange);
    super.dispose();
  }
}
