/// APRS one-to-one message thread screen.
///
/// Chat-bubble layout with per-message delivery status and a compose bar
/// at the bottom. Routing follows the unconditional Serial > BLE > APRS-IS
/// hierarchy owned by `TxService` — there is no per-message override.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../core/callsign/callsign_utils.dart';
import '../services/message_service.dart';
import '../services/notification_service.dart';
import '../services/station_settings_service.dart';
import '../ui/widgets/chat_bubble.dart';

// ---------------------------------------------------------------------------
// Thread display items (message bubbles interleaved with day dividers)
// ---------------------------------------------------------------------------

sealed class _ThreadItem {}

final class _MessageItem extends _ThreadItem {
  _MessageItem(this.entry);
  final MessageEntry entry;
}

final class _DayDividerItem extends _ThreadItem {
  _DayDividerItem(this.date);
  final DateTime date;
}

List<_ThreadItem> _buildThreadItems(List<MessageEntry> messages) {
  if (messages.isEmpty) return const [];
  final items = <_ThreadItem>[];
  DateTime? lastDate;
  for (final m in messages) {
    final d = DateTime(m.timestamp.year, m.timestamp.month, m.timestamp.day);
    if (lastDate == null || d != lastDate) {
      items.add(_DayDividerItem(d));
      lastDate = d;
    }
    items.add(_MessageItem(m));
  }
  return items;
}

class MessageThreadScreen extends StatefulWidget {
  const MessageThreadScreen({super.key, required this.peerCallsign});

  final String peerCallsign;

  @override
  State<MessageThreadScreen> createState() => _MessageThreadScreenState();
}

class _MessageThreadScreenState extends State<MessageThreadScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  late final NotificationService _notifService;

  @override
  void initState() {
    super.initState();
    _notifService = context.read<NotificationService>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<MessageService>().markRead(widget.peerCallsign);
      _notifService.setActiveThread(widget.peerCallsign);
    });
  }

  @override
  void dispose() {
    _notifService.setActiveThread(null);
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _inputCtrl.clear();
    await context.read<MessageService>().sendMessage(widget.peerCallsign, text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final messageService = context.watch<MessageService>();
    final isLicensed = context.select<StationSettingsService, bool>(
      (s) => s.isLicensed,
    );
    final myAddr = context.select<StationSettingsService, String>(
      (s) => normalizeCallsign(s.fullAddress),
    );
    final showOther = context.select<MessageService, bool>(
      (s) => s.showOtherSsids,
    );

    final conv = messageService.conversationWith(widget.peerCallsign);
    final allMessages = conv?.messages ?? [];
    final messages = allMessages
        .where((m) => showOther || !m.isCrossSsid(myAddr))
        .toList();
    final items = _buildThreadItems(messages);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            _PeerAvatar(callsign: widget.peerCallsign),
            const SizedBox(width: 12),
            Expanded(
              child: Text(widget.peerCallsign, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? const _EmptyThread()
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 8,
                    ),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final item = items[i];
                      return switch (item) {
                        _DayDividerItem(date: final d) => _DayDivider(date: d),
                        _MessageItem(entry: final e) => _MessageBubble(
                          entry: e,
                          peerCallsign: widget.peerCallsign,
                          myAddr: myAddr,
                        ),
                      };
                    },
                  ),
          ),
          if (isLicensed)
            _ComposeBar(controller: _inputCtrl, onSend: _send)
          else
            const _UnlicensedComposeBar(),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.entry,
    required this.peerCallsign,
    required this.myAddr,
  });

  final MessageEntry entry;
  final String peerCallsign;

  /// Operator's own normalized full address (e.g. 'KM4TJO' or 'KM4TJO-9').
  /// Used to detect cross-SSID messages and show the addressee badge.
  final String myAddr;

  String _ssidSuffix(String addressee) {
    final upper = addressee.trim().toUpperCase();
    final dashIdx = upper.lastIndexOf('-');
    return dashIdx == -1 ? upper : upper.substring(dashIdx);
  }

  Widget _statusIcon(BuildContext context, MessageStatus status, int retry) {
    return switch (status) {
      MessageStatus.pending => const Icon(Symbols.hourglass_empty, size: 14),
      MessageStatus.acked => Icon(
        Symbols.check_circle,
        size: 14,
        color: Colors.green.shade600,
      ),
      MessageStatus.retrying => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Symbols.refresh, size: 14, color: Colors.orange),
          const SizedBox(width: 2),
          Text(
            '$retry/5',
            style: const TextStyle(fontSize: 10, color: Colors.orange),
          ),
        ],
      ),
      MessageStatus.failed => const Icon(
        Symbols.cancel,
        size: 14,
        color: Colors.red,
      ),
      MessageStatus.rejected => const Icon(
        Symbols.block,
        size: 14,
        color: Colors.red,
      ),
      MessageStatus.cancelled => Icon(
        Symbols.do_not_disturb_on,
        size: 14,
        color: Colors.grey.shade500,
      ),
    };
  }

  /// Shows a context menu anchored to [globalPosition] with actions relevant
  /// to the current message status. No-ops for incoming messages or messages
  /// in a terminal/unactionable state.
  void _showContextMenu(BuildContext context, Offset globalPosition) {
    if (!entry.isOutgoing) return;

    final canCancel =
        entry.status == MessageStatus.pending ||
        entry.status == MessageStatus.retrying;
    final canResend = entry.status == MessageStatus.failed;
    if (!canCancel && !canResend) return;

    // Deliver platform-standard long-press haptic feedback.
    // On Android this maps to HapticFeedbackConstants.LONG_PRESS.
    // On iOS this triggers the default UIFeedbackGenerator vibration.
    // On desktop this is a no-op.
    HapticFeedback.vibrate();

    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      globalPosition & Size.zero,
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: position,
      items: [
        if (canCancel)
          const PopupMenuItem(
            value: 'cancel',
            child: ListTile(
              leading: Icon(Symbols.cancel_schedule_send),
              title: Text('Cancel'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (canResend)
          const PopupMenuItem(
            value: 'resend',
            child: ListTile(
              leading: Icon(Symbols.send),
              title: Text('Resend'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    ).then((action) {
      if (!context.mounted) return;
      final svc = context.read<MessageService>();
      if (action == 'cancel') {
        svc.cancelMessage(entry.localId, peerCallsign);
      } else if (action == 'resend') {
        svc.resendMessage(entry.localId, peerCallsign);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isOut = entry.isOutgoing;

    // Direct bubbles add a trailing slot for:
    //   - cross-SSID addressee badge (incoming only)
    //   - ACK / retry / failure status icon (outgoing only)
    Widget? meta;
    if (!isOut && entry.isCrossSsid(myAddr)) {
      meta = _CrossSsidBadge(suffix: _ssidSuffix(entry.addressee!));
    } else if (isOut) {
      meta = _statusIcon(context, entry.status, entry.retryCount);
    }

    final bubble = ChatBubble(
      text: entry.text,
      timestamp: entry.timestamp,
      isOutgoing: isOut,
      metaTrailing: meta,
    );

    // Only outgoing messages in an actionable state get the context menu.
    final canCancel =
        entry.status == MessageStatus.pending ||
        entry.status == MessageStatus.retrying;
    final canResend = entry.status == MessageStatus.failed;
    if (!isOut || (!canCancel && !canResend)) return bubble;

    return GestureDetector(
      // Mobile: long press
      onLongPressStart: (d) => _showContextMenu(context, d.globalPosition),
      // Desktop: right click
      onSecondaryTapUp: (d) => _showContextMenu(context, d.globalPosition),
      child: bubble,
    );
  }
}

/// Cross-SSID addressee indicator ("to -7") shown inside the meta slot of an
/// incoming direct-message bubble. Picks its colour from the surrounding
/// [DefaultTextStyle] / [IconTheme] so it blends with whichever bubble
/// colour-scheme it lands in.
class _CrossSsidBadge extends StatelessWidget {
  const _CrossSsidBadge({required this.suffix});
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final baseColor = DefaultTextStyle.of(context).style.color ?? Colors.black;
    return Tooltip(
      message: 'Addressed to this SSID',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: baseColor.withAlpha(120), width: 0.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'to ',
                style: TextStyle(color: baseColor.withAlpha(150)),
              ),
              TextSpan(
                text: suffix,
                style: TextStyle(
                  color: baseColor.withAlpha(220),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            style: const TextStyle(fontSize: 10),
          ),
        ),
      ),
    );
  }
}

class _ComposeBar extends StatefulWidget {
  const _ComposeBar({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  State<_ComposeBar> createState() => _ComposeBarState();
}

class _ComposeBarState extends State<_ComposeBar> {
  static const _maxLength = 67;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(() => setState(() {}));
  }

  int get _remaining => _maxLength - widget.controller.text.length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSend = widget.controller.text.trim().isNotEmpty;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: theme.dividerColor, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: widget.controller,
                maxLength: _maxLength,
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => widget.onSend(),
                decoration: InputDecoration(
                  hintText: 'Message',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  counterText: '',
                  suffix: Text(
                    '$_remaining',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: _remaining < 10
                          ? theme.colorScheme.error
                          : theme.colorScheme.outline,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              icon: const Icon(Icons.send_rounded),
              tooltip: 'Send',
              style: IconButton.styleFrom(foregroundColor: Colors.white),
              onPressed: canSend ? widget.onSend : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Centered day marker (e.g. "Today", "Yesterday", "Mon, Apr 20") shown
/// between message bubbles whenever the calendar date changes.
class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.date});

  final DateTime date;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (date == today) return 'Today';
    if (date == yesterday) return 'Yesterday';
    final wd = _weekdays[date.weekday - 1];
    final mo = _months[date.month - 1];
    if (date.year == now.year) return '$wd, $mo ${date.day}';
    return '$wd, $mo ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: theme.colorScheme.outlineVariant.withAlpha(120),
              height: 1,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _label(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: theme.colorScheme.outlineVariant.withAlpha(120),
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyThread extends StatelessWidget {
  const _EmptyThread();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No messages yet.\nSay hello!',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

/// Shown in place of [_ComposeBar] when the user is unlicensed.
class _UnlicensedComposeBar extends StatelessWidget {
  const _UnlicensedComposeBar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: theme.dividerColor, width: 0.5),
          ),
        ),
        child: Text(
          'An amateur radio license is required to send messages.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// Small SSID avatar shown in the thread's AppBar title, matching the
/// conversation-list avatar style for continuity.
class _PeerAvatar extends StatelessWidget {
  const _PeerAvatar({required this.callsign});

  final String callsign;

  String _ssidLabel(String c) {
    final upper = c.trim().toUpperCase();
    final dashIdx = upper.lastIndexOf('-');
    return dashIdx == -1 ? '0' : upper.substring(dashIdx);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CircleAvatar(
      radius: 16,
      backgroundColor: theme.colorScheme.primaryContainer,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          _ssidLabel(callsign),
          style: TextStyle(
            color: theme.colorScheme.onPrimaryContainer,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
