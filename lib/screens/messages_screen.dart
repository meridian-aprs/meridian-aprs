/// APRS messages thread list screen.
///
/// Shows all conversations sorted by most recent activity. Compose button
/// opens [ComposeMessageSheet] to start a new thread.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../services/message_service.dart';
import '../ui/utils/platform_route.dart';
import '../ui/widgets/compose_message_sheet.dart';
import 'message_thread_screen.dart';

class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  void _openCompose(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const ComposeMessageSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<MessageService>();
    final conversations = service.conversations;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          if (_isDesktop)
            IconButton(
              icon: const Icon(Symbols.edit_square),
              tooltip: 'New message',
              onPressed: () => _openCompose(context),
            ),
        ],
      ),
      body: conversations.isEmpty
          ? _EmptyState(onCompose: () => _openCompose(context))
          : ListView.separated(
              itemCount: conversations.length,
              separatorBuilder: (context, index) =>
                  const Divider(indent: 72, height: 1),
              itemBuilder: (ctx, i) {
                final conv = conversations[i];
                return _ConversationTile(
                  conversation: conv,
                  onTap: () {
                    service.markRead(conv.peerCallsign);
                    Navigator.push(
                      context,
                      buildPlatformRoute(
                        (_) => MessageThreadScreen(
                          peerCallsign: conv.peerCallsign,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
      floatingActionButton: _isDesktop
          ? null
          : FloatingActionButton(
              heroTag: 'compose_fab',
              tooltip: 'New message',
              onPressed: () => _openCompose(context),
              child: const Icon(Symbols.edit_square),
            ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.onTap});

  final Conversation conversation;
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
    final hasUnread = conversation.unreadCount > 0;
    final lastMsg = conversation.lastMessage;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Text(
          conversation.peerCallsign.substring(0, 1),
          style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
        ),
      ),
      title: Text(
        conversation.peerCallsign,
        style: TextStyle(
          fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: lastMsg != null
          ? Text(
              lastMsg.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
              ),
            )
          : null,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _formatTime(conversation.lastActivity),
            style: theme.textTheme.labelSmall,
          ),
          if (hasUnread) ...[
            const SizedBox(height: 4),
            Badge(label: Text('${conversation.unreadCount}')),
          ],
        ],
      ),
      onTap: onTap,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCompose});

  final VoidCallback onCompose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
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
            'Tap compose to start a conversation.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Symbols.edit_square),
            label: const Text('Compose'),
            onPressed: onCompose,
          ),
        ],
      ),
    );
  }
}
