import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../services/beaconing_service.dart';
import '../../../services/station_settings_service.dart';
import '../../../ui/utils/platform_route.dart';
import '../../../ui/widgets/aprs_symbol_widget.dart';
import '../../../ui/widgets/callsign_field.dart';
import '../../../ui/widgets/symbol_picker_dialog.dart';
import '../../location_picker_screen.dart';
import '../widgets/section_header.dart';

class MyStationSettingsContent extends StatefulWidget {
  const MyStationSettingsContent({super.key});

  @override
  State<MyStationSettingsContent> createState() =>
      _MyStationSettingsContentState();
}

class _MyStationSettingsContentState extends State<MyStationSettingsContent> {
  late final TextEditingController _callsignCtrl;
  late final TextEditingController _commentCtrl;
  late final TextEditingController _latCtrl;
  late final TextEditingController _lonCtrl;
  late final FocusNode _callsignFocus;
  late final FocusNode _commentFocus;

  @override
  void initState() {
    super.initState();
    final s = context.read<StationSettingsService>();
    _callsignCtrl = TextEditingController(text: s.callsign);
    _commentCtrl = TextEditingController(text: s.comment);
    _latCtrl = TextEditingController(
      text: s.manualLat != null ? s.manualLat!.toStringAsFixed(6) : '',
    );
    _lonCtrl = TextEditingController(
      text: s.manualLon != null ? s.manualLon!.toStringAsFixed(6) : '',
    );
    _callsignFocus = FocusNode()
      ..addListener(() {
        if (!_callsignFocus.hasFocus) {
          context.read<StationSettingsService>().setCallsign(
            _callsignCtrl.text,
          );
        }
      });
    _commentFocus = FocusNode()
      ..addListener(() {
        if (!_commentFocus.hasFocus) {
          context.read<StationSettingsService>().setComment(_commentCtrl.text);
        }
      });
  }

  @override
  void dispose() {
    _callsignCtrl.dispose();
    _commentCtrl.dispose();
    _latCtrl.dispose();
    _lonCtrl.dispose();
    _callsignFocus.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<StationSettingsService>();

    final isLicensed = service.isLicensed;

    return ListView(
      children: [
        const SectionHeader('My Station'),
        SwitchListTile.adaptive(
          title: const Text('Licensed amateur radio operator'),
          subtitle: const Text(
            'Required to transmit. Turn off to use Meridian in receive-only '
            'mode (no beacons, messages, or bulletins are sent).',
          ),
          value: isLicensed,
          onChanged: (v) =>
              context.read<StationSettingsService>().setIsLicensed(v),
        ),
        // Everything below depends on having a license: identity fields
        // (callsign, SSID, address) only matter for outgoing packets —
        // APRS-IS receive-only mode auto-logs in as `N0CALL/-1` per
        // ADR-045 — and symbol / comment / position source only feed
        // outgoing beacons. Hide the lot in receive-only mode so the
        // screen reflects what actually has effect.
        if (!isLicensed)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Text(
              'Receive-only mode is on. Turn on the switch above to '
              'configure your callsign, SSID, symbol, comment, and beacon '
              'position.',
            ),
          ),
        if (isLicensed) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: CallsignField(
              controller: _callsignCtrl,
              focusNode: _callsignFocus,
              label: 'Callsign',
              onChanged: (_) {},
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: DropdownButtonFormField<int>(
              decoration: const InputDecoration(
                labelText: 'SSID',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Symbols.tag),
              ),
              initialValue: service.ssid,
              items: List.generate(16, (i) {
                final label = switch (i) {
                  0 => '0 — No suffix',
                  1 => '1 — Digipeater',
                  2 => '2 — Generic',
                  3 => '3 — Generic',
                  4 => '4 — Generic',
                  5 => '5 — Portable',
                  6 => '6 — Special',
                  7 => '7 — Handheld',
                  8 => '8 — Boat',
                  9 => '9 — Vehicle',
                  10 => '10 — Internet',
                  11 => '11 — Aircraft',
                  12 => '12 — Balloon',
                  13 => '13 — Bike',
                  14 => '14 — ATV/GPS',
                  _ => '15 — Satellite',
                };
                return DropdownMenuItem(value: i, child: Text(label));
              }),
              onChanged: (v) {
                if (v != null) {
                  context.read<StationSettingsService>().setSsid(v);
                }
              },
            ),
          ),
          ListTile(
            dense: true,
            title: const Text('Your address'),
            subtitle: Text(
              service.fullAddress.isEmpty ? '—' : service.fullAddress,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          // Symbol, comment, and position source only matter for outgoing
          // beacons. They live inside the same licensed-only block as the
          // identity fields so the receive-only view collapses to just the
          // Licensed switch.
          _SymbolPickerTile(
            symbolTable: service.symbolTable,
            symbolCode: service.symbolCode,
            onChanged: (table, code) {
              context.read<StationSettingsService>().setSymbol(table, code);
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextFormField(
              controller: _commentCtrl,
              focusNode: _commentFocus,
              decoration: const InputDecoration(
                labelText: 'Comment',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Symbols.comment),
                hintText: 'e.g. Meridian APRS',
                counterText: '',
              ),
              maxLength: 36,
              onEditingComplete: () => FocusScope.of(context).unfocus(),
              onChanged: (v) => setState(() {}),
              buildCounter:
                  (_, {required currentLength, required isFocused, maxLength}) {
                    return Text(
                      '$currentLength / ${maxLength ?? 36}',
                      style: Theme.of(context).textTheme.bodySmall,
                    );
                  },
            ),
          ),
          const SectionHeader('Position Source'),
          _LocationSourcePicker(latCtrl: _latCtrl, lonCtrl: _lonCtrl),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}

class _SymbolPickerTile extends StatelessWidget {
  const _SymbolPickerTile({
    required this.symbolTable,
    required this.symbolCode,
    required this.onChanged,
  });

  final String symbolTable;
  final String symbolCode;
  final void Function(String table, String code) onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: AprsSymbolWidget(
        symbolTable: symbolTable,
        symbolCode: symbolCode,
        size: 28,
      ),
      title: const Text('Symbol'),
      subtitle: Text(symbolName(symbolTable, symbolCode)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final result = await showDialog<AprsSymbolEntry>(
          context: context,
          builder: (_) => SymbolPickerDialog(
            currentTable: symbolTable,
            currentCode: symbolCode,
          ),
        );
        if (result != null) {
          onChanged(result.table, result.code);
        }
      },
    );
  }
}

class _LocationSourcePicker extends StatelessWidget {
  const _LocationSourcePicker({required this.latCtrl, required this.lonCtrl});

  final TextEditingController latCtrl;
  final TextEditingController lonCtrl;

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<StationSettingsService>();
    final beaconing = context.watch<BeaconingService>();
    final gpsUnavailable = beaconing.gpsUnsupported;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: SegmentedButton<LocationSource>(
            segments: [
              ButtonSegment(
                value: LocationSource.gps,
                icon: const Icon(Symbols.gps_fixed),
                label: const Text('GPS'),
                tooltip: gpsUnavailable
                    ? 'GPS not available on this platform'
                    : 'Use live GPS position',
              ),
              const ButtonSegment(
                value: LocationSource.manual,
                icon: Icon(Symbols.edit_location),
                label: Text('Manual'),
                tooltip: 'Use manually entered coordinates',
              ),
            ],
            selected: {svc.locationSource},
            onSelectionChanged: (s) {
              if (gpsUnavailable && s.first == LocationSource.gps) return;
              svc.setLocationSource(s.first);
            },
          ),
        ),
        if (gpsUnavailable && svc.locationSource == LocationSource.gps)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(
              children: [
                Icon(
                  Symbols.warning,
                  size: 16,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'GPS is not available on this platform. '
                    'Switch to Manual to enter coordinates.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (svc.locationSource == LocationSource.manual) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: latCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Latitude',
                      border: OutlineInputBorder(),
                      hintText: '39.0000',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    onEditingComplete: () => _savePosition(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: lonCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Longitude',
                      border: OutlineInputBorder(),
                      hintText: '-77.0000',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    onEditingComplete: () => _savePosition(context),
                  ),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: FilledButton.tonal(
                    onPressed: () => _savePosition(context),
                    child: const Text('Set'),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: OutlinedButton.icon(
              icon: const Icon(Symbols.map, size: 18),
              label: const Text('Pick on map…'),
              onPressed: () => _openPicker(context, svc),
            ),
          ),
          if (svc.hasManualPosition)
            ListTile(
              dense: true,
              leading: const Icon(Symbols.location_on),
              title: Text(
                '${svc.manualLat!.toStringAsFixed(6)}°, '
                '${svc.manualLon!.toStringAsFixed(6)}°',
              ),
              trailing: IconButton(
                icon: const Icon(Symbols.location_off),
                tooltip: 'Clear manual position',
                color: Theme.of(context).colorScheme.error,
                onPressed: () {
                  latCtrl.clear();
                  lonCtrl.clear();
                  context.read<StationSettingsService>().clearManualPosition();
                },
              ),
            ),
          if (!svc.hasManualPosition)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'No position set — beacons will not transmit until '
                'coordinates are entered above.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ],
    );
  }

  void _savePosition(BuildContext context) {
    final lat = double.tryParse(latCtrl.text.trim());
    final lon = double.tryParse(lonCtrl.text.trim());
    if (lat == null || lon == null) return;
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return;
    context.read<StationSettingsService>().setManualPosition(lat, lon);
    FocusScope.of(context).unfocus();
  }

  Future<void> _openPicker(
    BuildContext context,
    StationSettingsService svc,
  ) async {
    final initial = svc.hasManualPosition
        ? LatLng(svc.manualLat!, svc.manualLon!)
        : null;
    final result = await Navigator.of(context).push<LatLng>(
      buildPlatformRoute((_) => LocationPickerScreen(initial: initial)),
    );
    if (result != null && context.mounted) {
      latCtrl.text = result.latitude.toStringAsFixed(6);
      lonCtrl.text = result.longitude.toStringAsFixed(6);
      context.read<StationSettingsService>().setManualPosition(
        result.latitude,
        result.longitude,
      );
    }
  }
}
