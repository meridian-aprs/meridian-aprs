/// Compose / edit screen for outgoing bulletins (spec §4.5, ADR-057).
///
/// Single-page form — not a wizard. The user picks type (General / named
/// Group), line number, group name (if Group), body, TX interval, expiry,
/// and per-transport flags. Edit mode pre-populates; changing body or
/// addressee resets `transmissionCount` + `lastTransmittedAt` per ADR-057
/// (handled by `BulletinService.updateOutgoingContent`).
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../models/bulletin.dart';
import '../models/outgoing_bulletin.dart';
import '../services/bulletin_service.dart';

enum _BulletinType { general, groupNamed }

class BulletinComposeScreen extends StatefulWidget {
  const BulletinComposeScreen({super.key, this.existing});

  /// When non-null, the form is in edit mode and pre-populates fields from
  /// this row.
  final OutgoingBulletin? existing;

  @override
  State<BulletinComposeScreen> createState() => _BulletinComposeScreenState();
}

class _BulletinComposeScreenState extends State<BulletinComposeScreen> {
  late _BulletinType _type;
  late String _lineNumber;
  late final TextEditingController _groupName;
  late final TextEditingController _body;
  late int _intervalSeconds;
  late int _expiryHours;
  late bool _viaRf;
  late bool _viaAprsIs;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final ob = widget.existing;
    if (ob != null) {
      final parsed = _parseAddressee(ob.addressee);
      _type = parsed.type;
      _lineNumber = parsed.lineNumber;
      _groupName = TextEditingController(text: parsed.groupName ?? '');
      _body = TextEditingController(text: ob.body);
      _intervalSeconds = ob.intervalSeconds;
      // Best-effort reverse-map absolute expiry → delta-hours dropdown by
      // computing hours between createdAt and expiresAt. Falls through to
      // nearest supported bucket.
      final deltaHours = ob.expiresAt
          .difference(ob.createdAt)
          .inHours
          .clamp(2, 48);
      _expiryHours = BulletinService.expiryOptionsHours.reduce(
        (a, b) => (a - deltaHours).abs() < (b - deltaHours).abs() ? a : b,
      );
      _viaRf = ob.viaRf;
      _viaAprsIs = ob.viaAprsIs;
    } else {
      _type = _BulletinType.general;
      _lineNumber = '0';
      _groupName = TextEditingController();
      _body = TextEditingController();
      _intervalSeconds = 1800;
      _expiryHours = 24;
      _viaRf = true;
      _viaAprsIs = true;
    }
  }

  @override
  void dispose() {
    _groupName.dispose();
    _body.dispose();
    super.dispose();
  }

  String _composeAddressee() {
    if (_type == _BulletinType.general) return 'BLN$_lineNumber';
    return 'BLN$_lineNumber${_groupName.text.trim().toUpperCase()}';
  }

  bool get _formValid {
    if (_body.text.trim().isEmpty) return false;
    if (!_viaRf && !_viaAprsIs) return false;
    if (_type == _BulletinType.groupNamed) {
      final group = _groupName.text.trim().toUpperCase();
      if (group.isEmpty) return false;
      if (!RegExp(r'^[A-Z0-9]{1,5}$').hasMatch(group)) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lineNumberOptions = _type == _BulletinType.general
        ? const ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9']
        : const [
            '0',
            '1',
            '2',
            '3',
            '4',
            '5',
            '6',
            '7',
            '8',
            '9',
            'A',
            'B',
            'C',
            'D',
            'E',
            'F',
            'G',
            'H',
            'I',
            'J',
            'K',
            'L',
            'M',
            'N',
            'O',
            'P',
            'Q',
            'R',
            'S',
            'T',
            'U',
            'V',
            'W',
            'X',
            'Y',
            'Z',
          ];

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit bulletin' : 'New bulletin')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Type', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<_BulletinType>(
            segments: const [
              ButtonSegment(
                value: _BulletinType.general,
                label: Text('General (BLN0–9)'),
              ),
              ButtonSegment(
                value: _BulletinType.groupNamed,
                label: Text('Named group'),
              ),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() {
              _type = s.first;
              // Reset line number if switching from groupNamed's letters.
              if (_type == _BulletinType.general &&
                  !RegExp(r'^[0-9]$').hasMatch(_lineNumber)) {
                _lineNumber = '0';
              }
            }),
          ),
          const SizedBox(height: 20),
          Text('Slot', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(
            'Replaces the # in BLN#. Different slots let you run multiple '
            'bulletins at once — receivers overwrite same-slot bulletins '
            'from the same source.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _lineNumber,
            items: [
              for (final v in lineNumberOptions)
                DropdownMenuItem(value: v, child: Text(v)),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _lineNumber = v);
            },
          ),
          if (_type == _BulletinType.groupNamed) ...[
            const SizedBox(height: 20),
            Text('Group name', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            TextField(
              controller: _groupName,
              maxLength: 5,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: 'e.g. WX, SRARC',
                helperText: '1–5 uppercase letters / digits',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: 20),
          Text('Body', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _body,
            maxLength: 67,
            maxLines: 3,
            minLines: 2,
            decoration: const InputDecoration(
              hintText: 'Bulletin body (up to 67 chars)',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          Text('Transmit interval', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _intervalSeconds,
            items: [
              for (final v in BulletinService.intervalOptionsSeconds)
                DropdownMenuItem(value: v, child: Text(_intervalLabel(v))),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _intervalSeconds = v);
            },
          ),
          const SizedBox(height: 20),
          Text('Expires in', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _expiryHours,
            items: [
              for (final h in BulletinService.expiryOptionsHours)
                DropdownMenuItem(value: h, child: Text('${h}h')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _expiryHours = v);
            },
          ),
          const SizedBox(height: 20),
          Text('Transports', style: theme.textTheme.labelLarge),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Via RF (TNC)'),
            subtitle: const Text('Uses the Advanced-mode "Bulletin path".'),
            value: _viaRf,
            onChanged: (v) => setState(() => _viaRf = v),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Via APRS-IS'),
            value: _viaAprsIs,
            onChanged: (v) => setState(() => _viaAprsIs = v),
          ),
          if (!_viaRf && !_viaAprsIs)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Select at least one transport.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: Icon(_isEdit ? Symbols.save : Symbols.send),
                  label: Text(_isEdit ? 'Save changes' : 'Start transmitting'),
                  onPressed: (_formValid && !_saving) ? _submit : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _intervalLabel(int seconds) {
    if (seconds == 0) return 'One-shot';
    if (seconds < 3600) return '${seconds ~/ 60} min';
    return '${seconds ~/ 3600} hr';
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    final bulletins = context.read<BulletinService>();
    final addressee = _composeAddressee();
    final expiresAt = DateTime.now().add(Duration(hours: _expiryHours));
    try {
      if (_isEdit) {
        final ob = widget.existing!;
        if (ob.addressee != addressee || ob.body != _body.text) {
          await bulletins.updateOutgoingContent(
            ob.id,
            addressee: addressee,
            body: _body.text,
          );
        }
        await bulletins.updateOutgoingSchedule(
          ob.id,
          intervalSeconds: _intervalSeconds,
          expiresAt: expiresAt,
          viaRf: _viaRf,
          viaAprsIs: _viaAprsIs,
        );
      } else {
        await bulletins.createOutgoing(
          addressee: addressee,
          body: _body.text,
          intervalSeconds: _intervalSeconds,
          expiresAt: expiresAt,
          viaRf: _viaRf,
          viaAprsIs: _viaAprsIs,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } on ArgumentError catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Invalid: ${e.message}')));
    }
  }
}

class _ParsedAddressee {
  _ParsedAddressee(this.type, this.lineNumber, this.groupName);
  final _BulletinType type;
  final String lineNumber;
  final String? groupName;
}

_ParsedAddressee _parseAddressee(String addressee) {
  // Valid form: BLN + line (0-9 or A-Z) + optional 1-5 char group name.
  final trimmed = addressee.trim().toUpperCase();
  if (!trimmed.startsWith('BLN') || trimmed.length < 4) {
    // Fallback — unlikely but safe default so the form still opens.
    return _ParsedAddressee(_BulletinType.general, '0', null);
  }
  final line = trimmed.substring(3, 4);
  final rest = trimmed.length > 4 ? trimmed.substring(4) : '';
  if (rest.isEmpty && RegExp(r'^[0-9]$').hasMatch(line)) {
    return _ParsedAddressee(_BulletinType.general, line, null);
  }
  return _ParsedAddressee(
    _BulletinType.groupNamed,
    line,
    rest.isEmpty ? null : rest,
  );
}

/// Derive the default BulletinCategory from an addressee. Exposed for the
/// "My bulletins" UI which wants to colour-code differently per category.
BulletinCategory categoryOfAddressee(String addressee) {
  final parsed = _parseAddressee(addressee);
  return parsed.type == _BulletinType.general
      ? BulletinCategory.general
      : BulletinCategory.groupNamed;
}
