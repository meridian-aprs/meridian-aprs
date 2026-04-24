/// Groups tab body inside [MessagesScreen].
///
/// Lists the user's enabled [GroupSubscription]s with reply-mode icon,
/// per-group unread badge (from `MessageService.conversationForGroup`), and
/// last-message preview. Empty / disabled-state copy routes the user to
/// Settings → Messaging → Groups to manage their subscriptions.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/group_subscription.dart';
import '../services/group_subscription_service.dart';
import '../services/message_service.dart';

class GroupsTab extends StatelessWidget {
  const GroupsTab({super.key, required this.onOpenGroup});

  /// Called when the user taps a group tile. Receives the bare group name
  /// (not the `#GROUP:` key).
  final ValueChanged<String> onOpenGroup;

  @override
  Widget build(BuildContext context) {
    final groups = context.watch<GroupSubscriptionService>();
    final messages = context.watch<MessageService>();

    // Respect user order (matcher-semantics) so the tab reads the same as
    // Settings. Show all — enabled + disabled — with the disabled ones dimmed,
    // because a disabled group still holds historical messages the user may
    // want to see.
    final subs = groups.subscriptions;
    if (subs.isEmpty) {
      return const _GroupsEmptyState();
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: subs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (ctx, i) {
        final sub = subs[i];
        final conv = messages.conversationForGroup(sub.name);
        return _GroupTile(
          sub: sub,
          conversation: conv,
          onTap: () => onOpenGroup(sub.name),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Group tile
// ---------------------------------------------------------------------------

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.sub,
    required this.conversation,
    required this.onTap,
  });

  final GroupSubscription sub;
  final Conversation? conversation;
  final VoidCallback onTap;

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasUnread = (conversation?.unreadCount ?? 0) > 0;
    final last = conversation?.lastMessage;
    final icon = sub.replyMode == ReplyMode.sender
        ? Symbols.campaign
        : Symbols.forum;

    // Build the preview: "<sender>: <text>". For group messages the
    // originator matters as much as the body.
    String? preview;
    String? previewSender;
    if (last != null) {
      previewSender = last.isOutgoing ? 'You' : last.fromCallsign;
      preview = last.text;
    }

    final statusIcons = <Widget>[
      if (!sub.enabled)
        Tooltip(
          message: 'Group disabled — incoming messages are not matched',
          child: Icon(
            Symbols.pause_circle,
            size: 16,
            color: theme.colorScheme.outline,
          ),
        ),
      if (!sub.notify)
        Tooltip(
          message: 'Notifications off for this group',
          child: Icon(
            Symbols.notifications_off,
            size: 16,
            color: theme.colorScheme.outline,
          ),
        ),
    ];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(
          icon,
          color: sub.enabled
              ? theme.colorScheme.primary
              : theme.colorScheme.outline,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                sub.name,
                style: TextStyle(
                  fontWeight: hasUnread ? FontWeight.bold : FontWeight.w600,
                  color: sub.enabled
                      ? null
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            for (final w in statusIcons) ...[const SizedBox(width: 6), w],
          ],
        ),
        subtitle: preview == null
            ? Text(
                sub.replyMode == ReplyMode.sender
                    ? 'No messages — replies route to sender'
                    : 'No messages — replies route to group',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : Text.rich(
                TextSpan(
                  children: [
                    if (previewSender != null)
                      TextSpan(
                        text: '$previewSender: ',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    TextSpan(text: preview),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (conversation != null)
              Text(
                _formatTime(conversation!.lastActivity),
                style: theme.textTheme.labelSmall,
              ),
            if (hasUnread) ...[
              const SizedBox(height: 4),
              Badge(label: Text('${conversation!.unreadCount}')),
            ],
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _GroupsEmptyState extends StatelessWidget {
  const _GroupsEmptyState();

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
            Text(
              'No group subscriptions yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Add groups like CQ, QST, or a club name in '
              'Settings → Messaging → Groups.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
