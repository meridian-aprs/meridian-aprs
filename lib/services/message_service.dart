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

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/packet/aprs_packet.dart';
import '../core/packet/aprs_encoder.dart';
import 'station_settings_service.dart';
import 'station_service.dart';
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
  MessageStatus status;
  int retryCount;
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
  MessageService(this._settings, this._tx, StationService stations) {
    _incomingSub = stations.packetStream.listen(_onPacket);
  }

  final StationSettingsService _settings;
  final TxService _tx;

  static const _keyCounter = 'message_id_counter';
  static const _retryDelays = [30, 60, 120, 240, 480]; // seconds (APRS spec)

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

  /// All conversations sorted by most recent activity (newest first).
  List<Conversation> get conversations {
    final list = _conversations.values.toList()
      ..sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
    return list;
  }

  /// Total unread message count across all conversations.
  int get totalUnread =>
      _conversations.values.fold(0, (sum, c) => sum + c.unreadCount);

  /// Returns the conversation for [peerCallsign], or null if none exists.
  Conversation? conversationWith(String peerCallsign) =>
      _conversations[peerCallsign.toUpperCase()];

  // ---------------------------------------------------------------------------
  // Public mutators
  // ---------------------------------------------------------------------------

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
    final myAddress = _settings.fullAddress.toUpperCase();

    // Only process packets addressed to this station.
    if (packet.addressee.toUpperCase() != myAddress) return;

    final source = packet.source.trim().toUpperCase();
    final text = packet.message;
    final wireId = packet.messageId;

    // Detect ACK: message text starts with "ack".
    if (text.toLowerCase().startsWith('ack') && wireId == null) {
      final ackId = text.substring(3).trim();
      _handleAck(source, ackId);
      return;
    }

    // Detect ACK with no text (rare spec variant).
    if (text.toLowerCase() == 'ack' ||
        (wireId != null && text.toLowerCase().startsWith('ack'))) {
      final ackId = wireId ?? text.substring(3).trim();
      _handleAck(source, ackId);
      return;
    }

    // Detect REJ.
    if (text.toLowerCase().startsWith('rej')) {
      final rejId = text.length > 3 ? text.substring(3).trim() : (wireId ?? '');
      _handleRej(source, rejId);
      return;
    }

    // Inbound message — deduplicate.
    final dedupeKey = '$source:${wireId ?? text}';
    if (_seenInbound.contains(dedupeKey)) return;
    _seenInbound.add(dedupeKey);

    final entry = MessageEntry(
      localId: dedupeKey,
      wireId: wireId,
      text: text,
      timestamp: packet.receivedAt,
      isOutgoing: false,
    );

    final conv = _getOrCreateConversation(source);
    conv.messages.add(entry);
    conv.lastActivity = packet.receivedAt;
    conv.unreadCount++;

    // Send ACK immediately.
    if (wireId != null && wireId.isNotEmpty) {
      _transmitAck(source, wireId);
    }

    notifyListeners();
  }

  void _handleAck(String peer, String ackId) {
    final ackKey = '$peer:$ackId';
    if (_seenAcks.contains(ackKey)) return;
    _seenAcks.add(ackKey);

    final conv = _conversations[peer];
    if (conv == null) return;

    for (final entry in conv.messages) {
      if (entry.isOutgoing && entry.wireId == ackId) {
        _retryTimers[entry.localId]?.cancel();
        _retryTimers.remove(entry.localId);
        entry.status = MessageStatus.acked;
        break;
      }
    }
    notifyListeners();
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
  }

  // ---------------------------------------------------------------------------
  // Internal — retry scheduler
  // ---------------------------------------------------------------------------

  void _scheduleRetry(MessageEntry entry, String peer, {required int attempt}) {
    if (attempt >= _retryDelays.length) {
      entry.status = MessageStatus.failed;
      notifyListeners();
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
