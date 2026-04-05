/// APRS one-to-one message thread screen.
///
/// Chat-bubble layout with per-message delivery status and a compose bar
/// at the bottom. The RF / APRS-IS transport toggle is in the app bar.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../services/message_service.dart';
import '../services/tx_service.dart';

class MessageThreadScreen extends StatefulWidget {
  const MessageThreadScreen({super.key, required this.peerCallsign});

  final String peerCallsign;

  @override
  State<MessageThreadScreen> createState() => _MessageThreadScreenState();
}

class _MessageThreadScreenState extends State<MessageThreadScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    // Mark conversation as read when thread is opened.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MessageService>().markRead(widget.peerCallsign);
    });
  }

  @override
  void dispose() {
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
    final txService = context.watch<TxService>();
    final conv = messageService.conversationWith(widget.peerCallsign);
    final messages = conv?.messages ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.peerCallsign),
        actions: [
          // RF / APRS-IS transport toggle
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Tooltip(
              message: !txService.tncAvailable ? 'TNC not connected' : '',
              child: SegmentedButton<TxTransportPref>(
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  ButtonSegment(
                    value: TxTransportPref.aprsIs,
                    icon: const Icon(Symbols.wifi),
                    label: const Text('IS'),
                    enabled: txService.aprsIsAvailable,
                  ),
                  ButtonSegment(
                    value: TxTransportPref.tnc,
                    icon: const Icon(Symbols.settings_input_antenna),
                    label: const Text('RF'),
                    enabled: txService.tncAvailable,
                  ),
                ],
                selected: {
                  txService.preference == TxTransportPref.auto
                      ? txService.effective
                      : txService.preference,
                },
                onSelectionChanged: (modes) {
                  if (modes.isNotEmpty) {
                    context.read<TxService>().setPreference(modes.first);
                  }
                },
              ),
            ),
          ),
        ],
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
                    itemCount: messages.length,
                    itemBuilder: (_, i) => _MessageBubble(
                      entry: messages[i],
                      peerCallsign: widget.peerCallsign,
                    ),
                  ),
          ),
          _ComposeBar(controller: _inputCtrl, onSend: _send),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.entry, required this.peerCallsign});

  final MessageEntry entry;
  final String peerCallsign;

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
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
    final theme = Theme.of(context);
    final isOut = entry.isOutgoing;

    final bgColor = isOut
        ? theme.colorScheme.primary
        : theme.colorScheme.secondaryContainer;
    final fgColor = isOut
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSecondaryContainer;

    final bubble = Align(
      alignment: isOut ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isOut ? 16 : 4),
              bottomRight: Radius.circular(isOut ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: isOut
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Text(entry.text, style: TextStyle(color: fgColor)),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(entry.timestamp),
                    style: TextStyle(
                      fontSize: 10,
                      color: fgColor.withAlpha(160),
                    ),
                  ),
                  if (isOut) ...[
                    const SizedBox(width: 6),
                    IconTheme(
                      data: IconThemeData(color: fgColor.withAlpha(180)),
                      child: _statusIcon(
                        context,
                        entry.status,
                        entry.retryCount,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
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
