/// APRS messages screen with three segmented tabs (Direct / Groups / Bulletins).
///
/// Direct tab preserves v0.14 behavior byte-for-byte. Groups tab lists the
/// user's enabled subscriptions; tap opens the group channel. Bulletins tab
/// shows the chronological feed gated by `BulletinService.showBulletins` and
/// the location-unknown banner. See ADR-059.
library;

import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../core/callsign/callsign_utils.dart';
import '../services/message_service.dart';
import '../services/station_settings_service.dart';
import '../ui/utils/platform_route.dart';
import '../ui/widgets/compose_message_sheet.dart';
import 'bulletins_tab.dart';
import 'group_channel_screen.dart';
import 'groups_tab.dart';
import 'message_thread_screen.dart';

/// Tabs in the Messages screen's segmented control.
enum MessagesTab { direct, groups, bulletins }

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  MessagesTab _tab = MessagesTab.direct;

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
    final isLicensed = context.select<StationSettingsService, bool>(
      (s) => s.isLicensed,
    );

    final directUnread = service.totalUnread;
    final groupUnread = service.totalGroupUnread;

    final Widget body = switch (_tab) {
      MessagesTab.direct => _DirectTab(
        service: service,
        isLicensed: isLicensed,
      ),
      MessagesTab.groups => GroupsTab(
        onOpenGroup: (groupName) {
          service.markRead('#GROUP:$groupName');
          Navigator.push(
            context,
            buildPlatformRoute((_) => GroupChannelScreen(groupName: groupName)),
          );
        },
      ),
      MessagesTab.bulletins => const BulletinsTab(),
    };

    // Only show the FAB on the Direct tab — group send UI + bulletin compose
    // live on their own surfaces (PR 4 wires both).
    final showFab = _tab == MessagesTab.direct && isLicensed && !_isDesktop;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          if (_tab == MessagesTab.direct && _isDesktop && isLicensed)
            IconButton(
              icon: const Icon(Symbols.edit_square),
              tooltip: 'New message',
              onPressed: () => _openCompose(context),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: _MessagesTabSwitcher(
              current: _tab,
              directUnread: directUnread,
              groupUnread: groupUnread,
              onChanged: (t) => setState(() => _tab = t),
            ),
          ),
        ),
      ),
      body: body,
      floatingActionButton: showFab
          ? FloatingActionButton(
              heroTag: 'compose_fab',
              tooltip: 'New message',
              onPressed: () => _openCompose(context),
              child: const Icon(Symbols.edit_square),
            )
          : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Segmented control — adaptive per platform
// ---------------------------------------------------------------------------

class _MessagesTabSwitcher extends StatelessWidget {
  const _MessagesTabSwitcher({
    required this.current,
    required this.directUnread,
    required this.groupUnread,
    required this.onChanged,
  });

  final MessagesTab current;
  final int directUnread;
  final int groupUnread;
  final ValueChanged<MessagesTab> onChanged;

  @override
  Widget build(BuildContext context) {
    // iOS → Cupertino sliding segmented control (no badges — Cupertino doesn't
    // support per-segment trailing content. Unread counts surface via the tab
    // content itself in the iOS flow.)
    if (!kIsWeb && Platform.isIOS) {
      return CupertinoSlidingSegmentedControl<MessagesTab>(
        groupValue: current,
        onValueChanged: (v) {
          if (v != null) onChanged(v);
        },
        children: const {
          MessagesTab.direct: Padding(
            padding: EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            child: Text('Direct'),
          ),
          MessagesTab.groups: Padding(
            padding: EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            child: Text('Groups'),
          ),
          MessagesTab.bulletins: Padding(
            padding: EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            child: Text('Bulletins'),
          ),
        },
      );
    }

    // Material M3 SegmentedButton with unread badges as icons.
    return SegmentedButton<MessagesTab>(
      segments: [
        ButtonSegment(
          value: MessagesTab.direct,
          icon: _UnreadBadge(count: directUnread),
          label: const Text('Direct'),
        ),
        ButtonSegment(
          value: MessagesTab.groups,
          icon: _UnreadBadge(count: groupUnread),
          label: const Text('Groups'),
        ),
        const ButtonSegment(
          value: MessagesTab.bulletins,
          label: Text('Bulletins'),
        ),
      ],
      selected: {current},
      onSelectionChanged: (s) => onChanged(s.first),
      showSelectedIcon: false,
    );
  }
}

/// Small wrapper so SegmentedButton's icon slot gracefully hides when the
/// count is zero (otherwise the layout jitters between segments).
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Badge(label: Text(count > 99 ? '99+' : '$count'));
  }
}

// ---------------------------------------------------------------------------
// Direct tab (existing v0.14 list, unchanged behavior)
// ---------------------------------------------------------------------------

class _DirectTab extends StatelessWidget {
  const _DirectTab({required this.service, required this.isLicensed});
  final MessageService service;
  final bool isLicensed;

  @override
  Widget build(BuildContext context) {
    final conversations = service.conversations;
    if (conversations.isEmpty) {
      return _DirectEmptyState(
        onCompose: isLicensed ? () => _openCompose(context) : null,
      );
    }
    return _DirectList(conversations: conversations, service: service);
  }

  void _openCompose(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const ComposeMessageSheet(),
    );
  }
}

// ---------------------------------------------------------------------------
// Direct list grouping helpers (unchanged from v0.14 implementation)
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

class _DirectList extends StatelessWidget {
  const _DirectList({required this.conversations, required this.service});
  final List<Conversation> conversations;
  final MessageService service;

  @override
  Widget build(BuildContext context) {
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

    return ListTile(
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
  }
}

// ---------------------------------------------------------------------------
// Direct tab empty state
// ---------------------------------------------------------------------------

class _DirectEmptyState extends StatelessWidget {
  const _DirectEmptyState({required this.onCompose});

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
