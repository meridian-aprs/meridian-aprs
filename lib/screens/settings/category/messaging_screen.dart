library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../core/callsign/callsign_utils.dart';
import '../../../models/bulletin_subscription.dart';
import '../../../models/group_subscription.dart';
import '../../../services/bulletin_service.dart';
import '../../../services/bulletin_subscription_service.dart';
import '../../../services/group_subscription_service.dart';
import '../../../services/message_service.dart';
import '../../../services/messaging_settings_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/station_settings_service.dart';
import '../advanced_mode_controller.dart';
import '../widgets/section_header.dart';

class MessagingSettingsContent extends StatelessWidget {
  const MessagingSettingsContent({super.key});

  @override
  Widget build(BuildContext context) {
    final messageService = context.watch<MessageService>();
    final notifService = context.watch<NotificationService>();
    final station = context.watch<StationSettingsService>();
    final groups = context.watch<GroupSubscriptionService>();
    final bulletinSubs = context.watch<BulletinSubscriptionService>();
    final bulletins = context.watch<BulletinService>();
    final messagingSettings = context.watch<MessagingSettingsService>();
    final advanced = context.watch<AdvancedModeController>();

    final baseCall = stripSsid(station.fullAddress);
    final fullCall = station.fullAddress.isEmpty
        ? 'your callsign'
        : station.fullAddress;
    final prefs = notifService.preferences;

    return ListView(
      children: [
        // -----------------------------------------------------------------
        // Cross-SSID messages (v0.14)
        // -----------------------------------------------------------------
        const SectionHeader('Cross-SSID Messages'),
        SwitchListTile.adaptive(
          title: const Text('Show messages to other SSIDs of my callsign'),
          subtitle: Text(
            "You'll see messages addressed to any SSID of $baseCall, "
            "not just $fullCall. Useful if you run multiple stations. "
            "Replies and acknowledgments still come from $fullCall only.",
          ),
          value: messageService.showOtherSsids,
          onChanged: (v) => messageService.setShowOtherSsids(v),
        ),
        if (messageService.showOtherSsids)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: SwitchListTile.adaptive(
              title: const Text('Notify for messages to other SSIDs'),
              subtitle: Text(
                'Get notifications for messages addressed to any SSID of '
                '$baseCall.',
              ),
              value: prefs.notifyOtherSsids,
              onChanged: (v) => notifService.setNotifyOtherSsids(v),
            ),
          ),

        // -----------------------------------------------------------------
        // Groups
        // -----------------------------------------------------------------
        const SectionHeader('Groups'),
        SwitchListTile.adaptive(
          title: const Text('Notify on group messages'),
          subtitle: const Text(
            'Master toggle — individual groups below can also be muted.',
          ),
          value: prefs.notifyGroups,
          onChanged: (v) => notifService.setNotifyGroups(v),
        ),
        _GroupsList(groups: groups),
        ListTile(
          leading: const Icon(Symbols.add),
          title: const Text('Add custom group'),
          subtitle: const Text('e.g. club net name or event'),
          onTap: () => _showGroupEditor(context, groups, existing: null),
        ),
        if (advanced.isEnabled)
          _AdvancedGroupPathTile(settings: messagingSettings),

        // -----------------------------------------------------------------
        // Bulletins
        // -----------------------------------------------------------------
        const SectionHeader('Bulletins'),
        SwitchListTile.adaptive(
          title: const Text('Show bulletins'),
          subtitle: const Text(
            'Display received bulletins on the Bulletins tab.',
          ),
          value: bulletins.showBulletins,
          onChanged: (v) => bulletins.setShowBulletins(v),
        ),
        SwitchListTile.adaptive(
          title: const Text('Notify on bulletins'),
          subtitle: const Text(
            'Master toggle — subscribed named groups below can also be muted.',
          ),
          value: prefs.notifyBulletins,
          onChanged: (v) => notifService.setNotifyBulletins(v),
        ),
        _BulletinRadiusTile(bulletins: bulletins),
        _BulletinRetentionTile(bulletins: bulletins),
        const SectionHeader('Named bulletin groups'),
        _BulletinSubscriptionsList(subscriptions: bulletinSubs),
        ListTile(
          leading: const Icon(Symbols.add),
          title: const Text('Add named group subscription'),
          subtitle: const Text('e.g. WX, CLUB — up to 5 chars'),
          onTap: () => _showBulletinSubscriptionAdder(context, bulletinSubs),
        ),
        if (advanced.isEnabled)
          _AdvancedBulletinPathTile(settings: messagingSettings),
        if (advanced.isEnabled)
          _MutedBulletinSourcesTile(settings: messagingSettings),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Groups list
// ---------------------------------------------------------------------------

class _GroupsList extends StatelessWidget {
  const _GroupsList({required this.groups});
  final GroupSubscriptionService groups;

  @override
  Widget build(BuildContext context) {
    final subs = groups.subscriptions;
    if (subs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text('No groups yet.'),
      );
    }
    // ReorderableListView requires a bounded height; use shrinkWrap inside
    // the outer scrolling ListView.
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: true,
      itemCount: subs.length,
      itemBuilder: (ctx, idx) {
        final sub = subs[idx];
        return _GroupListItem(key: ValueKey(sub.id), sub: sub, groups: groups);
      },
      onReorder: (oldIndex, newIndex) {
        if (newIndex > oldIndex) newIndex -= 1;
        final ids = subs.map((s) => s.id).toList();
        final moved = ids.removeAt(oldIndex);
        ids.insert(newIndex, moved);
        groups.reorder(ids);
      },
    );
  }
}

class _GroupListItem extends StatelessWidget {
  const _GroupListItem({super.key, required this.sub, required this.groups});
  final GroupSubscription sub;
  final GroupSubscriptionService groups;

  @override
  Widget build(BuildContext context) {
    final icon = sub.replyMode == ReplyMode.sender
        ? Symbols.campaign
        : Symbols.forum;
    final subtitle = [
      sub.matchMode == MatchMode.exact ? 'exact match' : 'prefix match',
      sub.replyMode == ReplyMode.sender ? 'reply to sender' : 'reply to group',
      if (sub.isBuiltin) 'built-in',
    ].join(' · ');

    return ListTile(
      leading: Icon(icon, color: sub.enabled ? null : Colors.grey),
      title: Row(
        children: [
          Expanded(child: Text(sub.name)),
          if (sub.isBuiltin) const Icon(Symbols.lock, size: 16),
        ],
      ),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Symbols.edit),
            tooltip: 'Edit',
            onPressed: () => _showGroupEditor(context, groups, existing: sub),
          ),
          Switch.adaptive(
            value: sub.enabled,
            onChanged: (v) => groups.update(sub.id, enabled: v),
          ),
        ],
      ),
      onTap: () => _showGroupEditor(context, groups, existing: sub),
    );
  }
}

// ---------------------------------------------------------------------------
// Group editor dialog
// ---------------------------------------------------------------------------

Future<void> _showGroupEditor(
  BuildContext context,
  GroupSubscriptionService groups, {
  required GroupSubscription? existing,
}) async {
  final result = await showDialog<_GroupEditorResult>(
    context: context,
    builder: (ctx) => _GroupEditorDialog(existing: existing),
  );
  if (result == null) return;
  if (result.delete && existing != null) {
    try {
      await groups.delete(existing.id);
    } on StateError {
      // Built-ins can't be deleted — UI shouldn't have offered the option.
    }
    return;
  }
  try {
    if (existing == null) {
      await groups.add(
        name: result.name,
        matchMode: result.matchMode,
        replyMode: result.replyMode,
        notify: result.notify,
        enabled: result.enabled,
      );
    } else {
      await groups.update(
        existing.id,
        name: existing.isBuiltin ? null : result.name,
        matchMode: result.matchMode,
        replyMode: result.replyMode,
        notify: result.notify,
        enabled: result.enabled,
      );
    }
  } on ArgumentError catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Invalid: ${e.message}')));
    }
  }
}

class _GroupEditorResult {
  _GroupEditorResult({
    required this.name,
    required this.matchMode,
    required this.replyMode,
    required this.notify,
    required this.enabled,
    this.delete = false,
  });
  final String name;
  final MatchMode matchMode;
  final ReplyMode replyMode;
  final bool notify;
  final bool enabled;
  final bool delete;
}

class _GroupEditorDialog extends StatefulWidget {
  const _GroupEditorDialog({required this.existing});
  final GroupSubscription? existing;

  @override
  State<_GroupEditorDialog> createState() => _GroupEditorDialogState();
}

class _GroupEditorDialogState extends State<_GroupEditorDialog> {
  late final TextEditingController _name;
  late MatchMode _matchMode;
  late ReplyMode _replyMode;
  late bool _notify;
  late bool _enabled;

  bool get _isEdit => widget.existing != null;
  bool get _isBuiltin => widget.existing?.isBuiltin ?? false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _matchMode = widget.existing?.matchMode ?? MatchMode.prefix;
    _replyMode = widget.existing?.replyMode ?? ReplyMode.group;
    _notify = widget.existing?.notify ?? true;
    _enabled = widget.existing?.enabled ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit group' : 'Add group'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              enabled: !_isBuiltin,
              textCapitalization: TextCapitalization.characters,
              maxLength: 9,
              decoration: InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. CQ, CLUB',
                helperText: _isBuiltin
                    ? 'Built-in groups cannot be renamed'
                    : '1–9 uppercase letters / digits',
              ),
              autofocus: !_isEdit,
            ),
            const SizedBox(height: 12),
            const Text('Match mode'),
            SegmentedButton<MatchMode>(
              segments: const [
                ButtonSegment(value: MatchMode.prefix, label: Text('Prefix')),
                ButtonSegment(value: MatchMode.exact, label: Text('Exact')),
              ],
              selected: {_matchMode},
              onSelectionChanged: (s) => setState(() => _matchMode = s.first),
            ),
            const SizedBox(height: 12),
            const Text('Default reply'),
            SegmentedButton<ReplyMode>(
              segments: const [
                ButtonSegment(
                  value: ReplyMode.sender,
                  icon: Icon(Symbols.campaign),
                  label: Text('To sender'),
                ),
                ButtonSegment(
                  value: ReplyMode.group,
                  icon: Icon(Symbols.forum),
                  label: Text('To group'),
                ),
              ],
              selected: {_replyMode},
              onSelectionChanged: (s) => setState(() => _replyMode = s.first),
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enabled'),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Notify'),
              value: _notify,
              onChanged: (v) => setState(() => _notify = v),
            ),
          ],
        ),
      ),
      actions: [
        if (_isEdit && !_isBuiltin)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(
                _GroupEditorResult(
                  name: widget.existing!.name,
                  matchMode: _matchMode,
                  replyMode: _replyMode,
                  notify: _notify,
                  enabled: _enabled,
                  delete: true,
                ),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim().toUpperCase();
            if (!_isBuiltin && !GroupSubscription.isValidName(name)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Invalid group name')),
              );
              return;
            }
            Navigator.of(context).pop(
              _GroupEditorResult(
                name: name,
                matchMode: _matchMode,
                replyMode: _replyMode,
                notify: _notify,
                enabled: _enabled,
              ),
            );
          },
          child: Text(_isEdit ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Bulletin radius / retention tiles
// ---------------------------------------------------------------------------

class _BulletinRadiusTile extends StatelessWidget {
  const _BulletinRadiusTile({required this.bulletins});
  final BulletinService bulletins;

  String _labelFor(int km) => switch (km) {
    0 => 'Map area only',
    -1 => 'Global',
    _ => '+$km km',
  };

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Symbols.radar),
      title: const Text('Bulletin radius'),
      subtitle: Text(_labelFor(bulletins.radiusKm)),
      trailing: const Icon(Symbols.chevron_right),
      onTap: () async {
        final selected = await showDialog<int>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Bulletin radius'),
            children: [
              for (final km in BulletinService.radiusOptionsKm)
                ListTile(
                  leading: Icon(
                    km == bulletins.radiusKm
                        ? Symbols.radio_button_checked
                        : Symbols.radio_button_unchecked,
                  ),
                  title: Text(_labelFor(km)),
                  onTap: () => Navigator.of(ctx).pop(km),
                ),
            ],
          ),
        );
        if (selected != null) await bulletins.setRadiusKm(selected);
      },
    );
  }
}

class _BulletinRetentionTile extends StatelessWidget {
  const _BulletinRetentionTile({required this.bulletins});
  final BulletinService bulletins;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Symbols.schedule),
      title: const Text('Retention'),
      subtitle: Text('${bulletins.retentionHours}h'),
      trailing: const Icon(Symbols.chevron_right),
      onTap: () async {
        final selected = await showDialog<int>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Bulletin retention'),
            children: [
              for (final h in BulletinService.retentionOptionsHours)
                ListTile(
                  leading: Icon(
                    h == bulletins.retentionHours
                        ? Symbols.radio_button_checked
                        : Symbols.radio_button_unchecked,
                  ),
                  title: Text('${h}h'),
                  onTap: () => Navigator.of(ctx).pop(h),
                ),
            ],
          ),
        );
        if (selected != null) await bulletins.setRetentionHours(selected);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Bulletin subscriptions
// ---------------------------------------------------------------------------

class _BulletinSubscriptionsList extends StatelessWidget {
  const _BulletinSubscriptionsList({required this.subscriptions});
  final BulletinSubscriptionService subscriptions;

  @override
  Widget build(BuildContext context) {
    final list = subscriptions.subscriptions;
    if (list.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          'No named-group subscriptions. Add one below to receive '
          'bulletins like BLN1WX or BLN2CLUB.',
        ),
      );
    }
    return Column(
      children: [
        for (final sub in list)
          ListTile(
            leading: const Icon(Symbols.campaign),
            title: Text(sub.groupName),
            subtitle: Text(sub.notify ? 'Notifications on' : 'Silent'),
            trailing: IconButton(
              icon: const Icon(Symbols.delete),
              onPressed: () => subscriptions.delete(sub.id),
            ),
          ),
      ],
    );
  }
}

Future<void> _showBulletinSubscriptionAdder(
  BuildContext context,
  BulletinSubscriptionService subs,
) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Add named-group subscription'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        maxLength: 5,
        decoration: const InputDecoration(
          labelText: 'Group name',
          hintText: 'e.g. WX, CLUB',
          helperText: '1–5 uppercase letters / digits',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
          child: const Text('Add'),
        ),
      ],
    ),
  );
  if (result == null || result.isEmpty) return;
  final normalized = result.toUpperCase();
  if (!BulletinSubscription.isValidName(normalized)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid name — 1–5 alphanumeric chars')),
      );
    }
    return;
  }
  try {
    await subs.add(groupName: normalized);
  } on ArgumentError catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Invalid: ${e.message}')));
    }
  }
}

// ---------------------------------------------------------------------------
// Advanced-mode tiles
// ---------------------------------------------------------------------------

class _AdvancedGroupPathTile extends StatelessWidget {
  const _AdvancedGroupPathTile({required this.settings});
  final MessagingSettingsService settings;

  @override
  Widget build(BuildContext context) {
    final value = settings.groupMessagePath.isEmpty
        ? 'Uses beacon path (${MessagingSettingsService.resolvedDefaultGroupMessagePath})'
        : settings.groupMessagePath;
    return ListTile(
      leading: const Icon(Symbols.route),
      title: const Text('Group message path'),
      subtitle: Text(value),
      trailing: const Icon(Symbols.edit),
      onTap: () => _showPathEditor(
        context,
        title: 'Group message path',
        initial: settings.groupMessagePath,
        hint: 'Leave empty to use beacon path',
        onSave: settings.setGroupMessagePath,
        allowEmpty: true,
      ),
    );
  }
}

class _AdvancedBulletinPathTile extends StatelessWidget {
  const _AdvancedBulletinPathTile({required this.settings});
  final MessagingSettingsService settings;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Symbols.route),
      title: const Text('Bulletin path'),
      subtitle: Text(settings.bulletinPath),
      trailing: const Icon(Symbols.edit),
      onTap: () => _showPathEditor(
        context,
        title: 'Bulletin path',
        initial: settings.bulletinPath,
        hint: 'Default: ${MessagingSettingsService.defaultBulletinPath}',
        onSave: settings.setBulletinPath,
        allowEmpty: false,
      ),
    );
  }
}

Future<void> _showPathEditor(
  BuildContext context, {
  required String title,
  required String initial,
  required String hint,
  required Future<void> Function(String) onSave,
  required bool allowEmpty,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String?>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'Digipeater path',
          hintText: hint,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (result == null) return;
  if (!allowEmpty && result.trim().isEmpty) return;
  try {
    await onSave(result);
  } on ArgumentError catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Invalid: ${e.message}')));
    }
  }
}

class _MutedBulletinSourcesTile extends StatelessWidget {
  const _MutedBulletinSourcesTile({required this.settings});
  final MessagingSettingsService settings;

  @override
  Widget build(BuildContext context) {
    final muted = settings.mutedBulletinSources.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Symbols.notifications_off),
          title: const Text('Muted bulletin sources'),
          subtitle: Text(
            muted.isEmpty
                ? 'No callsigns muted'
                : '${muted.length} callsign${muted.length == 1 ? '' : 's'} muted',
          ),
          trailing: IconButton(
            icon: const Icon(Symbols.add),
            onPressed: () => _showAddMutedSource(context, settings),
          ),
        ),
        for (final callsign in muted)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: ListTile(
              dense: true,
              title: Text(callsign),
              trailing: IconButton(
                icon: const Icon(Symbols.close),
                onPressed: () => settings.removeMutedBulletinSource(callsign),
              ),
            ),
          ),
      ],
    );
  }
}

Future<void> _showAddMutedSource(
  BuildContext context,
  MessagingSettingsService settings,
) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Mute bulletin source'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(
          labelText: 'Callsign (with or without SSID)',
          hintText: 'e.g. K5WX-15',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
          child: const Text('Mute'),
        ),
      ],
    ),
  );
  if (result == null || result.isEmpty) return;
  await settings.addMutedBulletinSource(result);
}
