/// Group channel screen — chronological feed for a single [GroupSubscription].
///
/// Each bubble shows the sender callsign prominently (per spec §4.3). The
/// compose bar adapts to the group's `replyMode`:
///
///   - `group`  → "Message to GROUPNAME"  [Send]
///   - `sender` → "Reply to sender callsign"  [Send]  + secondary "Send to group"
///
/// Replies route per the group's `replyMode`:
/// - `group`  → broadcast back to the group via `MessageService.sendGroupMessage`
/// - `sender` → direct 1:1 reply to the last-heard sender via
///   `MessageService.sendMessage` (direct thread opens so the operator can
///   watch the ACK).
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/group_subscription.dart';
import '../services/group_subscription_service.dart';
import '../services/message_service.dart';
import '../services/messaging_settings_service.dart';
import '../services/station_settings_service.dart';
import '../ui/utils/platform_route.dart';
import '../ui/widgets/chat_bubble.dart';
import 'message_thread_screen.dart';

class GroupChannelScreen extends StatefulWidget {
  const GroupChannelScreen({super.key, required this.groupName});

  final String groupName;

  @override
  State<GroupChannelScreen> createState() => _GroupChannelScreenState();
}

class _GroupChannelScreenState extends State<GroupChannelScreen> {
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  GroupSubscription? _resolveSubscription(GroupSubscriptionService groups) {
    final name = widget.groupName.toUpperCase();
    for (final s in groups.subscriptions) {
      if (s.name == name) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final groups = context.watch<GroupSubscriptionService>();
    final messages = context.watch<MessageService>();
    final isLicensed = context.select<StationSettingsService, bool>(
      (s) => s.isLicensed,
    );

    final sub = _resolveSubscription(groups);
    final conversation = messages.conversationForGroup(widget.groupName);
    final entries = conversation?.messages ?? const <MessageEntry>[];
    final lastIncoming = entries
        .where((e) => !e.isOutgoing)
        .cast<MessageEntry?>()
        .fold<MessageEntry?>(
          null,
          (prev, m) => m, // last element wins
        );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Icon(
              sub?.replyMode == ReplyMode.sender
                  ? Symbols.campaign
                  : Symbols.forum,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(widget.groupName)),
          ],
        ),
        bottom: sub == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(22),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    sub.replyMode == ReplyMode.sender
                        ? 'Replies route to the individual sender'
                        : 'Replies broadcast to the group',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
      ),
      body: Column(
        children: [
          Expanded(
            child: entries.isEmpty
                ? const _GroupChannelEmptyState()
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 8,
                    ),
                    itemCount: entries.length,
                    itemBuilder: (_, i) => _GroupBubble(entry: entries[i]),
                  ),
          ),
          if (!isLicensed)
            const _GroupUnlicensedBar()
          else if (sub == null)
            const _GroupMissingSubscriptionBar()
          else
            _GroupComposeBar(
              subscription: sub,
              lastSenderCallsign: lastIncoming?.fromCallsign,
              onSendToGroup: _sendToGroup,
              onSendToSender: _sendToSender,
            ),
        ],
      ),
    );
  }

  // --- Send paths -----------------------------------------------------------

  void _sendToGroup(String text) async {
    final messaging = context.read<MessagingSettingsService>();
    final messages = context.read<MessageService>();
    final rfPath = messaging.effectiveGroupMessagePath
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    await messages.sendGroupMessage(widget.groupName, text, rfPath: rfPath);
  }

  void _sendToSender(String text, String toCallsign) async {
    // Reply-to-sender always routes through the direct-message path so the
    // user sees ACK status and retries. Open the direct thread too so the
    // reply is visible immediately.
    final messages = context.read<MessageService>();
    await messages.sendMessage(toCallsign, text);
    if (!mounted) return;
    Navigator.push(
      context,
      buildPlatformRoute((_) => MessageThreadScreen(peerCallsign: toCallsign)),
    );
  }
}

// ---------------------------------------------------------------------------
// Bubble
// ---------------------------------------------------------------------------

class _GroupBubble extends StatelessWidget {
  const _GroupBubble({required this.entry});
  final MessageEntry entry;

  @override
  Widget build(BuildContext context) {
    // Sender attribution on incoming only — outgoing messages are already
    // right-aligned, so adding "You" is redundant and clutters the frame
    // (matches direct-message thread convention).
    final topLine = entry.isOutgoing ? null : entry.fromCallsign;
    return ChatBubble(
      text: entry.text,
      timestamp: entry.timestamp,
      isOutgoing: entry.isOutgoing,
      topLine: topLine,
    );
  }
}

// ---------------------------------------------------------------------------
// Compose bar (adaptive per reply_mode)
// ---------------------------------------------------------------------------

class _GroupComposeBar extends StatefulWidget {
  const _GroupComposeBar({
    required this.subscription,
    required this.lastSenderCallsign,
    required this.onSendToGroup,
    required this.onSendToSender,
  });

  final GroupSubscription subscription;
  final String? lastSenderCallsign;
  final void Function(String text) onSendToGroup;
  final void Function(String text, String toCallsign) onSendToSender;

  @override
  State<_GroupComposeBar> createState() => _GroupComposeBarState();
}

class _GroupComposeBarState extends State<_GroupComposeBar> {
  final _controller = TextEditingController();
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final can = _controller.text.trim().isNotEmpty;
      if (can != _canSend) setState(() => _canSend = can);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSenderMode = widget.subscription.replyMode == ReplyMode.sender;
    final hasLastSender = widget.lastSenderCallsign != null;
    final primaryHint = isSenderMode && hasLastSender
        ? 'Reply to ${widget.lastSenderCallsign}'
        : 'Message to ${widget.subscription.name}';

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    maxLength: 67,
                    maxLines: 3,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: primaryHint,
                      border: const OutlineInputBorder(),
                      counterText: '',
                    ),
                    onSubmitted: _canSend ? (_) => _primarySend() : null,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _canSend ? _primarySend : null,
                  icon: Icon(
                    isSenderMode && hasLastSender
                        ? Symbols.reply
                        : Symbols.send,
                  ),
                  tooltip: primaryHint,
                ),
              ],
            ),
            if (isSenderMode && hasLastSender)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _canSend
                      ? () {
                          widget.onSendToGroup(_controller.text.trim());
                          _controller.clear();
                        }
                      : null,
                  icon: const Icon(Symbols.forum, size: 18),
                  label: Text('Send to ${widget.subscription.name} instead'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _primarySend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final isSenderMode = widget.subscription.replyMode == ReplyMode.sender;
    if (isSenderMode && widget.lastSenderCallsign != null) {
      widget.onSendToSender(text, widget.lastSenderCallsign!);
    } else {
      widget.onSendToGroup(text);
    }
    _controller.clear();
  }
}

// ---------------------------------------------------------------------------
// Fallback states
// ---------------------------------------------------------------------------

class _GroupUnlicensedBar extends StatelessWidget {
  const _GroupUnlicensedBar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Text(
          'An amateur radio license is required to send group messages.',
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _GroupMissingSubscriptionBar extends StatelessWidget {
  const _GroupMissingSubscriptionBar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Text(
          'This group is no longer in your subscriptions — re-add it from '
          'Settings → Messaging → Groups to send messages.',
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _GroupChannelEmptyState extends StatelessWidget {
  const _GroupChannelEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.forum,
              size: 64,
              color: theme.colorScheme.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text('No messages yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Messages addressed to this group will appear here.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
