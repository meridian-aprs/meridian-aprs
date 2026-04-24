/// APRS one-to-one messaging service.
///
/// Implements APRS spec §14 message format with:
/// - Auto-incrementing message IDs (persisted across sessions)
/// - ACK/REJ handling
/// - Exponential retry backoff: 30/60/120/240/480 s (APRS spec)
/// - Duplicate detection on inbound messages and ACKs
///
/// See ADR-022 in docs/DECISIONS.md for retry interval rationale.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/callsign/addressee_matcher.dart';
import '../core/callsign/callsign_utils.dart';
import '../core/callsign/message_classification.dart';
import '../core/packet/aprs_encoder.dart';
import '../core/packet/aprs_packet.dart';
import '../models/group_subscription.dart';
import '../models/message_category.dart';
import 'bulletin_service.dart';
import 'group_subscription_service.dart';
import 'station_service.dart';
import 'station_settings_service.dart';
import 'tx_service.dart';

/// Delivery state of an outgoing message.
enum MessageStatus { pending, acked, retrying, failed, rejected, cancelled }

/// A single message in a conversation thread.
class MessageEntry {
  MessageEntry({
    required this.localId,
    required this.wireId,
    required this.text,
    required this.timestamp,
    required this.isOutgoing,
    this.addressee,
    this.fromCallsign,
    this.category = MessageCategory.direct,
    this.groupName,
    this.status = MessageStatus.pending,
    this.retryCount = 0,
  });

  /// Unique local identifier (used to key retry timers).
  final String localId;

  /// APRS wire message ID (e.g. `001`), null for incoming without ID.
  final String? wireId;

  final String text;
  final DateTime timestamp;
  final bool isOutgoing;

  /// Full callsign the message was addressed to (incoming only).
  final String? addressee;

  /// Full callsign of the packet source (incoming only). For direct
  /// conversations this equals the parent `Conversation.peerCallsign`; for
  /// group conversations (where the parent key is `#GROUP:<NAME>`) it is
  /// the only place the actual sender is preserved. Null for outgoing or
  /// for legacy-deserialized entries that predate this field (v0.14).
  final String? fromCallsign;

  /// Classification category from [AddresseeMatcher.classifyWithPrecedence].
  /// Defaults to [MessageCategory.direct] for legacy-safe deserialization —
  /// older entries without this key were all direct messages (v0.14-era).
  final MessageCategory category;

  /// The matched group subscription name when [category] is
  /// [MessageCategory.group]; null otherwise.
  final String? groupName;

  MessageStatus status;
  int retryCount;

  /// Returns true when this incoming message was addressed to a different SSID
  /// of the operator's callsign (i.e., cross-SSID capture).
  ///
  /// [myFullAddress] must be already normalized via [normalizeCallsign] and uppercased.
  /// Always returns false for outgoing messages or when [addressee] is null.
  bool isCrossSsid(String myFullAddress) =>
      !isOutgoing &&
      addressee != null &&
      normalizeCallsign(addressee!) != myFullAddress;
}

/// A conversation thread with a single remote callsign.
class Conversation {
  Conversation({required this.peerCallsign})
    : messages = [],
      unreadCount = 0,
      lastActivity = DateTime.now();

  final String peerCallsign;
  final List<MessageEntry> messages;
  int unreadCount;
  DateTime lastActivity;

  MessageEntry? get lastMessage => messages.isEmpty ? null : messages.last;
}

class MessageService extends ChangeNotifier {
  MessageService(
    this._settings,
    this._tx,
    StationService stations, {
    required GroupSubscriptionService groupSubscriptions,
    required BulletinService bulletins,
  }) : _groupSubscriptions = groupSubscriptions,
       _bulletins = bulletins {
    _incomingSub = stations.packetStream.listen(_onPacket);
  }

  final StationSettingsService _settings;
  final TxService _tx;
  final GroupSubscriptionService _groupSubscriptions;
  final BulletinService _bulletins;

  static const _keyCounter = 'message_id_counter';
  static const _keyPeers = 'msg_peers';
  static const _keyMessageDays = 'history_message_days';
  static const _keyShowOtherSsids = 'msg_show_other_ssids';
  static const _retryDelays = [30, 60, 120, 240, 480]; // seconds (APRS spec)

  /// Sentinel value meaning "keep forever" (no age-based pruning).
  static const int forever = 0;

  int _messageHistoryDays = 90;
  bool _showOtherSsids = false;

  static String _convKey(String peer) => 'msg_conv_$peer';

  // Active conversations keyed by peer callsign (uppercase, no padding).
  final _conversations = <String, Conversation>{};

  // Retry timers keyed by localId.
  final _retryTimers = <String, Timer>{};

  // Deduplication sets.
  final _seenInbound = <String>{}; // "source:wireId"
  final _seenAcks = <String>{}; // "peer:wireId"

  StreamSubscription<AprsPacket>? _incomingSub;

  // ---------------------------------------------------------------------------
  // Public read API
  // ---------------------------------------------------------------------------

  /// The operator's own callsign in normalized form (no '-0' suffix, uppercase).
  /// Used to derive cross-SSID status for incoming messages.
  String get myFullAddress => normalizeCallsign(_settings.fullAddress);

  bool get showOtherSsids => _showOtherSsids;

  /// True if [peerCallsign] is a group-conversation key (`#GROUP:<NAME>`).
  /// Group threads are stored in the same `_conversations` map as direct
  /// threads but are filtered out of the direct accessors below.
  static bool _isGroupKey(String peerCallsign) =>
      peerCallsign.startsWith('#GROUP:');

  /// Direct conversations, sorted by most recent activity (newest first).
  ///
  /// Excludes group threads. When [showOtherSsids] is false, also hides
  /// threads that contain only cross-SSID messages.
  List<Conversation> get conversations {
    final myAddr = myFullAddress;
    final list = _conversations.values.where((conv) {
      if (_isGroupKey(conv.peerCallsign)) return false;
      if (_showOtherSsids) return true;
      return conv.messages.any((m) => m.isOutgoing || !m.isCrossSsid(myAddr));
    }).toList()..sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
    return list;
  }

  /// All *direct* conversations sorted by most recent activity — unfiltered
  /// by cross-SSID preference. Used by NotificationService to dispatch
  /// notifications regardless of the display preference. Group threads are
  /// excluded (group-message notifications route via a separate channel
  /// added in PR 5).
  List<Conversation> get allConversations {
    final list =
        _conversations.values
            .where((c) => !_isGroupKey(c.peerCallsign))
            .toList()
          ..sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
    return list;
  }

  /// Group conversations sorted by most recent activity. Each entry's
  /// [Conversation.peerCallsign] starts with the `#GROUP:` prefix; use
  /// [groupNameOf] to extract the bare group name.
  List<Conversation> get groupConversations {
    final list =
        _conversations.values.where((c) => _isGroupKey(c.peerCallsign)).toList()
          ..sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
    return list;
  }

  /// Extract the group name from a `#GROUP:<NAME>` conversation key.
  /// Returns null if [peerCallsign] is not a group key.
  static String? groupNameOf(String peerCallsign) {
    if (!_isGroupKey(peerCallsign)) return null;
    return peerCallsign.substring('#GROUP:'.length);
  }

  /// Returns the conversation for a given group [name], or null if empty.
  Conversation? conversationForGroup(String name) =>
      _conversations[_groupConvKey(name.toUpperCase())];

  /// Max age of persisted messages in days. [forever] (0) means no age limit.
  int get messageHistoryDays => _messageHistoryDays;

  /// Total unread count across *direct* conversations only. Groups have
  /// their own counter.
  int get totalUnread => _conversations.values
      .where((c) => !_isGroupKey(c.peerCallsign))
      .fold(0, (sum, c) => sum + c.unreadCount);

  /// Total unread count across group conversations.
  int get totalGroupUnread => _conversations.values
      .where((c) => _isGroupKey(c.peerCallsign))
      .fold(0, (sum, c) => sum + c.unreadCount);

  /// Returns the conversation for [peerCallsign], or null if none exists.
  /// Accepts either a direct callsign or a `#GROUP:<NAME>` key.
  Conversation? conversationWith(String peerCallsign) =>
      _conversations[peerCallsign.toUpperCase()];

  // ---------------------------------------------------------------------------
  // Public mutators
  // ---------------------------------------------------------------------------

  /// Update the message history age limit in days ([forever] = no limit).
  ///
  /// Applies immediately: messages older than [days] are pruned from all
  /// conversations, and empty conversations are removed.
  Future<void> setMessageHistoryDays(int days) async {
    if (_messageHistoryDays == days) return;
    _messageHistoryDays = days;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyMessageDays, days);
    _pruneByAge(days);
    notifyListeners();
    _persist(); // ignore: unawaited_futures
  }

  Future<void> setShowOtherSsids(bool v) async {
    if (_showOtherSsids == v) return;
    _showOtherSsids = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowOtherSsids, v);
    notifyListeners();
  }

  /// Restore persisted conversations from [SharedPreferences].
  ///
  /// Call once after construction (before [runApp]). Messages that were
  /// [MessageStatus.pending] or [MessageStatus.retrying] when the app was last
  /// closed are demoted to [MessageStatus.failed] — their retry timers cannot
  /// be resumed, but the user can trigger [resendMessage] manually.
  Future<void> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    _messageHistoryDays = prefs.getInt(_keyMessageDays) ?? 90;
    _showOtherSsids = prefs.getBool(_keyShowOtherSsids) ?? false;

    final peersRaw = prefs.getString(_keyPeers);
    if (peersRaw == null) return;

    final peers = (jsonDecode(peersRaw) as List<dynamic>).cast<String>();
    for (final peer in peers) {
      final convRaw = prefs.getString(_convKey(peer));
      if (convRaw == null) continue;
      try {
        final conv = _convFromJson(jsonDecode(convRaw) as Map<String, dynamic>);
        _conversations[peer] = conv;
      } catch (e) {
        debugPrint('MessageService: failed to load conversation $peer: $e');
      }
    }

    // Drop messages that exceed the configured age limit.
    _pruneByAge(_messageHistoryDays);
    notifyListeners();
  }

  /// Send a group message to [groupName]. Group messages are never ACKed
  /// (ADR-055) — no retry scheduler, no wire ID. The outgoing entry is
  /// appended to the group's conversation thread so the user sees it echoed
  /// in the channel view (spec §6.6).
  ///
  /// [rfPath] overrides the default digipeater path for RF dispatch; null
  /// uses the encoder's hardcoded default. Callers (the group compose bar)
  /// pass `MessagingSettingsService.effectiveGroupMessagePath` split into a
  /// list.
  Future<void> sendGroupMessage(
    String groupName,
    String text, {
    List<String>? rfPath,
  }) async {
    final normalized = groupName.trim().toUpperCase();
    if (normalized.isEmpty) return;

    final line = AprsEncoder.encodeGroupMessage(
      fromCallsign: _settings.callsign.isEmpty ? 'NOCALL' : _settings.callsign,
      fromSsid: _settings.ssid,
      groupName: normalized,
      body: text,
    );
    await _tx.sendLine(line, digipeaterPath: rfPath);

    // Own-SSID echo — append to group conversation so the operator sees
    // their own send in the channel view. No wireId, no retry loop.
    final localId =
        'group_${normalized}_'
        '${DateTime.now().millisecondsSinceEpoch}';
    final entry = MessageEntry(
      localId: localId,
      wireId: null,
      text: text,
      timestamp: DateTime.now(),
      isOutgoing: true,
      category: MessageCategory.group,
      groupName: normalized,
      status: MessageStatus.acked, // groups have no ACK; mark as "delivered".
    );
    final conv = _getOrCreateConversation(_groupConvKey(normalized));
    conv.messages.add(entry);
    conv.lastActivity = entry.timestamp;
    notifyListeners();
    await _persist();
  }

  /// Send a message to [toCallsign].
  ///
  /// Creates a conversation if one doesn't exist. Starts the retry scheduler.
  Future<void> sendMessage(String toCallsign, String text) async {
    final peer = toCallsign.trim().toUpperCase();
    final wireId = await _nextMessageId();
    final localId =
        '${peer}_${wireId}_${DateTime.now().millisecondsSinceEpoch}';

    final entry = MessageEntry(
      localId: localId,
      wireId: wireId,
      text: text,
      timestamp: DateTime.now(),
      isOutgoing: true,
    );

    final conv = _getOrCreateConversation(peer);
    conv.messages.add(entry);
    conv.lastActivity = DateTime.now();

    await _transmitMessage(peer, text, wireId);
    _scheduleRetry(entry, peer, attempt: 0);
    notifyListeners();
    await _persist();
  }

  /// Cancel a pending or retrying outgoing message.
  ///
  /// Stops the retry timer. If an ACK arrives later it is still applied so the
  /// message will transition to [MessageStatus.acked] (the remote station may
  /// have received it before we gave up waiting).
  void cancelMessage(String localId, String peerCallsign) {
    _retryTimers[localId]?.cancel();
    _retryTimers.remove(localId);

    final conv = _conversations[peerCallsign.toUpperCase()];
    if (conv == null) return;
    for (final entry in conv.messages) {
      if (entry.localId == localId &&
          (entry.status == MessageStatus.pending ||
              entry.status == MessageStatus.retrying)) {
        entry.status = MessageStatus.cancelled;
        break;
      }
    }
    notifyListeners();
    _persist(); // ignore: unawaited_futures
  }

  /// Re-send a message that has reached [MessageStatus.failed].
  ///
  /// Resets retry state and transmits immediately, restarting the full retry
  /// schedule from the beginning.
  Future<void> resendMessage(String localId, String peerCallsign) async {
    final peer = peerCallsign.toUpperCase();
    final conv = _conversations[peer];
    if (conv == null) return;
    for (final entry in conv.messages) {
      if (entry.localId == localId && entry.status == MessageStatus.failed) {
        entry.status = MessageStatus.pending;
        entry.retryCount = 0;
        notifyListeners();
        if (entry.wireId != null) {
          await _transmitMessage(peer, entry.text, entry.wireId!);
        }
        _scheduleRetry(entry, peer, attempt: 0);
        await _persist();
        break;
      }
    }
  }

  /// Mark all messages in [peerCallsign]'s thread as read.
  void markRead(String peerCallsign) {
    final conv = _conversations[peerCallsign.toUpperCase()];
    if (conv == null) return;
    if (conv.unreadCount == 0) return;
    conv.unreadCount = 0;
    notifyListeners();
    _persist(); // ignore: unawaited_futures
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    for (final t in _retryTimers.values) {
      t.cancel();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Internal — incoming packet handling
  // ---------------------------------------------------------------------------

  void _onPacket(AprsPacket packet) {
    if (packet is! MessagePacket) return;

    // Classify the addressee via the load-bearing precedence order (ADR-055):
    // Bulletin → Direct → Group. Do not inline or reorder this call.
    final classification = AddresseeMatcher.classifyWithPrecedence(
      packet.addressee,
      _settings.operatorIdentity,
      _groupSubscriptions.enabledSubscriptions,
    );

    final source = packet.source.trim().toUpperCase();
    final text = packet.message;
    final wireId = packet.messageId;

    switch (classification) {
      case BulletinClassification(:final info):
        // Bulletins are never ACKed and never flow into Conversation threads.
        _bulletins.ingest(
          info: info,
          sourceCallsign: source,
          body: text,
          transport: packet.transportSource,
          receivedAt: packet.receivedAt,
        );
        return;

      case DirectClassification(:final isExactMatch):
        _handleDirect(
          packet: packet,
          source: source,
          text: text,
          wireId: wireId,
          isExactMatch: isExactMatch,
        );
        return;

      case GroupClassification(:final subscription):
        _handleGroup(
          packet: packet,
          source: source,
          text: text,
          wireId: wireId,
          subscription: subscription,
        );
        return;

      case NoneClassification():
        debugPrint(
          'MessageService: dropped packet — addressee="${packet.addressee.toUpperCase()}" '
          'myAddress="$myFullAddress"',
        );
        return;
    }
  }

  void _handleDirect({
    required MessagePacket packet,
    required String source,
    required String text,
    required String? wireId,
    required bool isExactMatch,
  }) {
    // ACK/REJ routing mirrors v0.14: only ACKs to our exact SSID resolve the
    // outgoing retry loop. Cross-SSID ACKs are logged but never applied to
    // our message table.
    if (packet.isAck) {
      debugPrint('MessageService: inbound ACK from=$source id=$wireId');
      if (isExactMatch) _handleAck(source, wireId ?? '');
      return;
    }
    if (packet.isRej) {
      if (isExactMatch) _handleRej(source, wireId ?? '');
      return;
    }

    final dedupeKey = '$source:${wireId ?? text}';
    if (_seenInbound.contains(dedupeKey)) return;
    _seenInbound.add(dedupeKey);

    final entry = MessageEntry(
      localId: dedupeKey,
      wireId: wireId,
      text: text,
      timestamp: packet.receivedAt,
      isOutgoing: false,
      addressee: packet.addressee.trim(),
      fromCallsign: source,
      category: MessageCategory.direct,
    );

    final conv = _getOrCreateConversation(source);
    conv.messages.add(entry);
    conv.lastActivity = packet.receivedAt;
    conv.unreadCount++;

    // ACK exact match only. Never ACK cross-SSID, group, or bulletin.
    if (isExactMatch && wireId != null && wireId.isNotEmpty) {
      _transmitAck(source, wireId); // ignore: unawaited_futures
    }

    notifyListeners();
    _persist(); // ignore: unawaited_futures
  }

  void _handleGroup({
    required MessagePacket packet,
    required String source,
    required String text,
    required String? wireId,
    required GroupSubscription subscription,
  }) {
    // Group messages are never ACKed — even if the wire carries a message-ID.
    // Discard ACK/REJ payloads addressed to a group (nonsense protocol-wise,
    // but we defensively ignore them to avoid corrupting any threading).
    if (packet.isAck || packet.isRej) return;

    // Dedupe on source+id+groupName — a retransmission within the same
    // conversation shouldn't double-post.
    final dedupeKey = 'group:${subscription.name}:$source:${wireId ?? text}';
    if (_seenInbound.contains(dedupeKey)) return;
    _seenInbound.add(dedupeKey);

    // PR 3 adds the Groups tab UI. For now, receive-side storage uses the
    // group name as the conversation key so all incoming messages for a
    // group land in a single thread the UI can pick up later.
    final entry = MessageEntry(
      localId: dedupeKey,
      wireId: wireId,
      text: text,
      timestamp: packet.receivedAt,
      isOutgoing: false,
      addressee: packet.addressee.trim(),
      fromCallsign: source,
      category: MessageCategory.group,
      groupName: subscription.name,
    );

    final conv = _getOrCreateConversation(_groupConvKey(subscription.name));
    conv.messages.add(entry);
    conv.lastActivity = packet.receivedAt;
    conv.unreadCount++;

    notifyListeners();
    _persist(); // ignore: unawaited_futures
  }

  /// Conversation-key prefix for group threads. Keeps group conversations in
  /// the same `_conversations` map as direct threads without colliding with
  /// real callsigns (no callsign starts with `#`).
  static String _groupConvKey(String groupName) => '#GROUP:$groupName';

  void _handleAck(String peer, String ackId) {
    final ackKey = '$peer:$ackId';
    if (_seenAcks.contains(ackKey)) {
      debugPrint('MessageService: ACK deduped peer=$peer id=$ackId');
      return;
    }
    _seenAcks.add(ackKey);

    final conv = _conversations[peer];
    if (conv == null) {
      debugPrint(
        'MessageService: ACK no conversation — peer=$peer '
        'known=${_conversations.keys.toList()}',
      );
      return;
    }

    var matched = false;
    for (final entry in conv.messages) {
      if (entry.isOutgoing && entry.wireId == ackId) {
        _retryTimers[entry.localId]?.cancel();
        _retryTimers.remove(entry.localId);
        entry.status = MessageStatus.acked;
        matched = true;
        break;
      }
    }
    if (!matched) {
      debugPrint(
        'MessageService: ACK no matching entry — peer=$peer id=$ackId '
        'outgoing wireIds=${conv.messages.where((e) => e.isOutgoing).map((e) => e.wireId).toList()}',
      );
    }
    notifyListeners();
    _persist(); // ignore: unawaited_futures
  }

  void _handleRej(String peer, String rejId) {
    final conv = _conversations[peer];
    if (conv == null) return;

    for (final entry in conv.messages) {
      if (entry.isOutgoing && entry.wireId == rejId) {
        _retryTimers[entry.localId]?.cancel();
        _retryTimers.remove(entry.localId);
        entry.status = MessageStatus.rejected;
        break;
      }
    }
    notifyListeners();
    _persist(); // ignore: unawaited_futures
  }

  // ---------------------------------------------------------------------------
  // Internal — retry scheduler
  // ---------------------------------------------------------------------------

  void _scheduleRetry(MessageEntry entry, String peer, {required int attempt}) {
    if (attempt >= _retryDelays.length) {
      entry.status = MessageStatus.failed;
      notifyListeners();
      _persist(); // ignore: unawaited_futures
      return;
    }

    final delay = Duration(seconds: _retryDelays[attempt]);
    _retryTimers[entry.localId] = Timer(delay, () async {
      // Check if already settled since scheduling.
      if (entry.status == MessageStatus.acked ||
          entry.status == MessageStatus.rejected ||
          entry.status == MessageStatus.cancelled) {
        return;
      }

      entry.status = MessageStatus.retrying;
      entry.retryCount = attempt + 1;
      notifyListeners();

      if (entry.wireId != null) {
        await _transmitMessage(peer, entry.text, entry.wireId!);
      }
      _scheduleRetry(entry, peer, attempt: attempt + 1);
    });
  }

  // ---------------------------------------------------------------------------
  // Internal — TX helpers
  // ---------------------------------------------------------------------------

  Future<void> _transmitMessage(
    String toCallsign,
    String text,
    String wireId,
  ) async {
    final line = AprsEncoder.encodeMessage(
      fromCallsign: _settings.callsign.isEmpty ? 'NOCALL' : _settings.callsign,
      fromSsid: _settings.ssid,
      toCallsign: toCallsign,
      text: text,
      messageId: wireId,
    );
    await _tx.sendLine(line);
  }

  Future<void> _transmitAck(String toCallsign, String wireId) async {
    final line = AprsEncoder.encodeAck(
      fromCallsign: _settings.callsign.isEmpty ? 'NOCALL' : _settings.callsign,
      fromSsid: _settings.ssid,
      toCallsign: toCallsign,
      messageId: wireId,
    );
    await _tx.sendLine(line);
  }

  // ---------------------------------------------------------------------------
  // Internal — conversation management
  // ---------------------------------------------------------------------------

  Conversation _getOrCreateConversation(String peer) {
    return _conversations.putIfAbsent(
      peer,
      () => Conversation(peerCallsign: peer),
    );
  }

  // ---------------------------------------------------------------------------
  // Internal — persistence
  // ---------------------------------------------------------------------------

  /// Persist all conversations to [SharedPreferences]. Fire-and-forget; callers
  /// do not need to await this.
  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final peers = _conversations.keys.toList();
    await prefs.setString(_keyPeers, jsonEncode(peers));
    for (final entry in _conversations.entries) {
      await prefs.setString(
        _convKey(entry.key),
        jsonEncode(_convToJson(entry.value)),
      );
    }
  }

  Map<String, dynamic> _convToJson(Conversation c) {
    // Omit messages older than the configured age limit before serialising.
    final msgs = _messageHistoryDays == forever
        ? c.messages
        : c.messages
              .where((e) => _withinAge(e.timestamp, _messageHistoryDays))
              .toList();
    return {
      'peer': c.peerCallsign,
      'unreadCount': c.unreadCount,
      'lastActivity': c.lastActivity.millisecondsSinceEpoch,
      'messages': msgs.map(_entryToJson).toList(),
    };
  }

  Conversation _convFromJson(Map<String, dynamic> json) {
    final conv = Conversation(peerCallsign: json['peer'] as String);
    conv.unreadCount = (json['unreadCount'] as int?) ?? 0;
    conv.lastActivity = DateTime.fromMillisecondsSinceEpoch(
      json['lastActivity'] as int,
    );
    final msgs = (json['messages'] as List<dynamic>?) ?? [];
    for (final m in msgs) {
      conv.messages.add(_entryFromJson(m as Map<String, dynamic>));
    }
    return conv;
  }

  Map<String, dynamic> _entryToJson(MessageEntry e) => {
    'localId': e.localId,
    'wireId': e.wireId,
    'text': e.text,
    'timestamp': e.timestamp.millisecondsSinceEpoch,
    'isOutgoing': e.isOutgoing,
    'addressee': e.addressee,
    'fromCallsign': e.fromCallsign,
    'category': e.category.name,
    'groupName': e.groupName,
    'status': e.status.name,
    'retryCount': e.retryCount,
  };

  /// Remove messages older than [days] from all conversations, then drop
  /// conversations that become empty as a result.
  void _pruneByAge(int days) {
    if (days == forever) return;
    _conversations.removeWhere((_, conv) {
      conv.messages.removeWhere((e) => !_withinAge(e.timestamp, days));
      return conv.messages.isEmpty;
    });
  }

  /// Returns true if [dt] is within [days] days of now.
  bool _withinAge(DateTime dt, int days) {
    if (days == forever) return true;
    return DateTime.now().difference(dt).inDays < days;
  }

  MessageEntry _entryFromJson(Map<String, dynamic> json) {
    final statusName = (json['status'] as String?) ?? 'failed';
    var status = MessageStatus.values.firstWhere(
      (s) => s.name == statusName,
      orElse: () => MessageStatus.failed,
    );
    // Timers can't be resumed after a restart — treat as failed so the user
    // can explicitly resend if needed.
    if (status == MessageStatus.pending || status == MessageStatus.retrying) {
      status = MessageStatus.failed;
    }
    // Legacy-safe: entries saved before v0.17 lack `category`/`groupName`.
    // They are all direct messages (cross-SSID handled via `addressee`).
    final categoryName = json['category'] as String?;
    final category = categoryName == null
        ? MessageCategory.direct
        : MessageCategory.values.firstWhere(
            (c) => c.name == categoryName,
            orElse: () => MessageCategory.direct,
          );
    return MessageEntry(
      localId: json['localId'] as String,
      wireId: json['wireId'] as String?,
      text: json['text'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      isOutgoing: (json['isOutgoing'] as bool?) ?? false,
      addressee: json['addressee'] as String?,
      fromCallsign: json['fromCallsign'] as String?,
      category: category,
      groupName: json['groupName'] as String?,
      status: status,
      retryCount: (json['retryCount'] as int?) ?? 0,
    );
  }

  // ---------------------------------------------------------------------------
  // Internal — message ID counter
  // ---------------------------------------------------------------------------

  Future<String> _nextMessageId() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_keyCounter) ?? 0;
    final next = (current % 999) + 1;
    await prefs.setInt(_keyCounter, next);
    return next.toString().padLeft(3, '0');
  }
}
