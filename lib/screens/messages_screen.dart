/// APRS messages thread list screen.
///
/// Shows all conversations sorted by most recent activity. Each base callsign
/// gets its own Card — single-SSID threads are a one-tile card; multi-SSID
/// threads show a base callsign header row followed by indented sub-rows,
/// all within the same card.
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
// Group model
// ---------------------------------------------------------------------------

final class _ConvGroup {
  _ConvGroup({required this.baseCallsign, required this.conversations});
  final String baseCallsign;
  final List<Conversation> conversations;
  bool get isMulti => conversations.length >= 2;
  int get totalUnread => conversations.fold(0, (sum, c) => sum + c.unreadCount);
}

List<_ConvGroup> _buildGroups(List<Conversation> conversations) {
  final byBase = <String, List<Conversation>>{};
  for (final conv in conversations) {
    final base = stripSsid(conv.peerCallsign);
    byBase.putIfAbsent(base, () => []).add(conv);
  }

  final groups = <_ConvGroup>[];
  final emitted = <String>{};

  for (final conv in conversations) {
    final base = stripSsid(conv.peerCallsign);
    if (emitted.contains(base)) continue;
    emitted.add(base);
    groups.add(_ConvGroup(baseCallsign: base, conversations: byBase[base]!));
  }
  return groups;
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

  List<Widget> _buildMultiCardChildren(
    BuildContext context,
    _ConvGroup group,
    MessageService service,
  ) {
    final children = <Widget>[
      _CardGroupHeader(
        baseCallsign: group.baseCallsign,
        totalUnread: group.totalUnread,
      ),
    ];
    for (var i = 0; i < group.conversations.length; i++) {
      if (i > 0) {
        children.add(
          const Divider(indent: 72, endIndent: 16, height: 1, thickness: 0.5),
        );
      }
      final c = group.conversations[i];
      children.add(
        _ConversationTile(
          conversation: c,
          onTap: () {
            service.markRead(c.peerCallsign);
            Navigator.push(
              context,
              buildPlatformRoute(
                (_) => MessageThreadScreen(peerCallsign: c.peerCallsign),
              ),
            );
          },
        ),
      );
    }
    return children;
  }

  Widget _buildList(
    BuildContext context,
    List<Conversation> conversations,
    MessageService service,
  ) {
    final groups = _buildGroups(conversations);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: groups.length,
      itemBuilder: (ctx, i) {
        final group = groups[i];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          clipBehavior: Clip.antiAlias,
          child: group.isMulti
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _buildMultiCardChildren(context, group, service),
                )
              : _ConversationTile(
                  conversation: group.conversations.first,
                  onTap: () {
                    final peer = group.conversations.first.peerCallsign;
                    service.markRead(peer);
                    Navigator.push(
                      context,
                      buildPlatformRoute(
                        (_) => MessageThreadScreen(peerCallsign: peer),
                      ),
                    );
                  },
                ),
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
          : _buildList(context, conversations, service),
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
// Card group header (shown only for multi-SSID groups)
// ---------------------------------------------------------------------------

class _CardGroupHeader extends StatelessWidget {
  const _CardGroupHeader({
    required this.baseCallsign,
    required this.totalUnread,
  });

  final String baseCallsign;
  final int totalUnread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        children: [
          Text(
            baseCallsign,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.tertiary,
              fontWeight: FontWeight.w700,
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

  /// Returns the SSID portion of [callsign] for use in the avatar.
  /// 'W1ABC-9' → '-9', 'W1ABC-15' → '-15', 'W1ABC' → '0'
  /// (APRS spec: a callsign with no SSID is equivalent to SSID -0.)
  String _ssidLabel(String callsign) {
    final upper = callsign.trim().toUpperCase();
    final dashIdx = upper.lastIndexOf('-');
    return dashIdx == -1 ? '0' : upper.substring(dashIdx);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasUnread = conversation.unreadCount > 0;
    final lastMsg = conversation.lastMessage;

    final tile = ListTile(
      tileColor: hasUnread
          ? theme.colorScheme.primaryContainer.withAlpha(60)
          : null,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            _ssidLabel(conversation.peerCallsign),
            style: TextStyle(
              color: theme.colorScheme.onPrimaryContainer,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
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
