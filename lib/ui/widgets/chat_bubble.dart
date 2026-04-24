/// Shared chat bubble used by both the direct-message thread view and the
/// group channel view. Visual frame (shape, colors, alignment, timestamp) is
/// identical across both surfaces; per-surface extras ride in optional slots:
///
///   - [topLine]      — sender attribution (group channels only).
///   - [metaTrailing] — status icon, cross-SSID badge, etc. (direct only).
///
/// Does NOT own gesture handling. Callers wrap in a [GestureDetector] or
/// similar when they need long-press/right-click menus (direct context menu).
library;

import 'package:flutter/material.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.text,
    required this.timestamp,
    required this.isOutgoing,
    this.topLine,
    this.metaTrailing,
    this.maxWidthFactor = 0.75,
  });

  /// Message body.
  final String text;

  final DateTime timestamp;

  /// True when this message is from the operator — renders with the primary
  /// colour on the right.
  final bool isOutgoing;

  /// Optional leading line above the body, rendered in accent colour and
  /// semibold. Use for sender attribution in group channels.
  final String? topLine;

  /// Optional widget rendered inline with the timestamp (right of it on
  /// outgoing, left of it on incoming). Use for status icons or badges.
  final Widget? metaTrailing;

  /// Max bubble width as a fraction of available screen width.
  final double maxWidthFactor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOut = isOutgoing;

    final bgColor = isOut
        ? theme.colorScheme.primary
        : theme.colorScheme.secondaryContainer;
    final fgColor = isOut
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSecondaryContainer;

    return Align(
      alignment: isOut ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * maxWidthFactor,
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
              if (topLine != null) ...[
                Text(
                  topLine!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    // Slightly lighter than the body so it reads as a label.
                    color: fgColor.withAlpha(200),
                  ),
                ),
                const SizedBox(height: 2),
              ],
              Text(text, style: TextStyle(color: fgColor)),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(timestamp),
                    style: TextStyle(
                      fontSize: 10,
                      color: fgColor.withAlpha(160),
                    ),
                  ),
                  if (metaTrailing != null) ...[
                    const SizedBox(width: 6),
                    IconTheme(
                      data: IconThemeData(color: fgColor.withAlpha(180)),
                      child: DefaultTextStyle.merge(
                        style: TextStyle(
                          fontSize: 10,
                          color: fgColor.withAlpha(180),
                        ),
                        child: metaTrailing!,
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
  }

  static String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}
