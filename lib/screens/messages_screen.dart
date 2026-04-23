/// APRS messages thread list screen.
///
/// Shows all conversations sorted by most recent activity. Conversations
/// sharing a base callsign are grouped under a collapsible header when
/// [MessageService.showOtherSsids] is active. Compose button opens
/// [ComposeMessageSheet] to start a new thread.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../core/callsign/callsign_utils.dart';
import '../services/message_service.dart';
import '../services/station_settings_service.dart';
import '../ui/utils/platform_route.dart';
import '../ui/widgets/compose_message_sheet.dart';
import 'message_thread_screen.dart';

// ---------------------------------------------------------------------------
// Display item types for the grouped list
// ---------------------------------------------------------------------------

sealed class _DisplayItem {}

final class _GroupHeader extends _DisplayItem {
  _GroupHeader({required this.baseCallsign, required this.conversations});
  final String baseCallsign;
  final List<Conversation> conversations;
  int get totalUnread => conversations.fold(0, (sum, c) => sum + c.unreadCount);
}

final class _ConvItem extends _DisplayItem {
  _ConvItem({required this.conversation, required this.isSubRow});
  final Conversation conversation;
  final bool isSubRow;
}

// ---------------------------------------------------------------------------
// Grouping helper
// ---------------------------------------------------------------------------

List<_DisplayItem> _buildGroupedItems(List<Conversation> conversations) {
  // Group conversations by base callsign.
  final byBase = <String, List<Conversation>>{};
  for (final conv in conversations) {
    final base = stripSsid(conv.peerCallsign);
    byBase.putIfAbsent(base, () => []).add(conv);
  }

  // Build display items, preserving the overall lastActivity sort order from
  // MessageService (conversations is already sorted newest-first).
  final items = <_DisplayItem>[];
  final emitted = <String>{};

  for (final conv in conversations) {
    final base = stripSsid(conv.peerCallsign);
    if (emitted.contains(base)) continue;
    emitted.add(base);

    final group = byBase[base]!;
    if (group.length >= 2) {
      items.add(_GroupHeader(baseCallsign: base, conversations: group));
      for (final c in group) {
        items.add(_ConvItem(conversation: c, isSubRow: true));
      }
    } else {
      items.add(_ConvItem(conversation: conv, isSubRow: false));
    }
  }
  return items;
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

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

  Widget _buildGroupedList(
    BuildContext context,
    List<Conversation> conversations,
    MessageService service,
  ) {
    final items = _buildGroupedItems(conversations);
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final item = items[i];
        if (item is _GroupHeader) {
          return _GroupHeaderTile(
            baseCallsign: item.baseCallsign,
            totalUnread: item.totalUnread,
          );
        }
        final convItem = item as _ConvItem;
        return _ConversationTile(
          conversation: convItem.conversation,
          isSubRow: convItem.isSubRow,
          onTap: () {
            service.markRead(convItem.conversation.peerCallsign);
            Navigator.push(
              context,
              buildPlatformRoute(
                (_) => MessageThreadScreen(
                  peerCallsign: convItem.conversation.peerCallsign,
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<MessageService>();
    final isLicensed = context.select<StationSettingsService, bool>(
      (s) => s.isLicensed,
    );
    final conversations = service.conversations;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          if (_isDesktop && isLicensed)
            IconButton(
              icon: const Icon(Symbols.edit_square),
              tooltip: 'New message',
              onPressed: () => _openCompose(context),
            ),
        ],
      ),
      body: conversations.isEmpty
          ? _EmptyState(
              onCompose: isLicensed ? () => _openCompose(context) : null,
            )
          : _buildGroupedList(context, conversations, service),
      floatingActionButton: (_isDesktop || !isLicensed)
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

// ---------------------------------------------------------------------------
// Group header tile
// ---------------------------------------------------------------------------

class _GroupHeaderTile extends StatelessWidget {
  const _GroupHeaderTile({
    required this.baseCallsign,
    required this.totalUnread,
  });

  final String baseCallsign;
  final int totalUnread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
      child: Row(
        children: [
          Text(
            baseCallsign,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.tertiary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          if (totalUnread > 0) Badge(label: Text('$totalUnread')),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Conversation tile
// ---------------------------------------------------------------------------

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.onTap,
    this.isSubRow = false,
  });

  final Conversation conversation;
  final VoidCallback onTap;
  final bool isSubRow;

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

    Widget tile = ListTile(
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

    if (isSubRow) {
      tile = Container(
        margin: const EdgeInsets.only(left: 20),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: theme.colorScheme.tertiaryContainer,
              width: 4,
            ),
          ),
        ),
        child: tile,
      );
    }
    return tile;
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCompose});

  /// Null when the user is unlicensed — hides the compose button.
  final VoidCallback? onCompose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final licensed = onCompose != null;
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
            licensed
                ? 'Tap compose to start a conversation.'
                : 'An amateur radio license is required to send messages.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          if (licensed) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Symbols.edit_square),
              label: const Text('Compose'),
              onPressed: onCompose,
            ),
          ],
        ],
      ),
    );
  }
}
