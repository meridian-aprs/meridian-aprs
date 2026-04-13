import 'dart:io' show Platform;

import 'package:url_launcher/url_launcher.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import 'package:latlong2/latlong.dart';

import '../services/background_service_manager.dart';
import '../services/beaconing_service.dart';
import '../services/ios_background_service.dart';
import 'location_picker_screen.dart';
import '../services/message_service.dart';
import '../services/station_service.dart';
import '../services/station_settings_service.dart';
import '../ui/utils/distance_formatter.dart';
import '../ui/utils/platform_route.dart';
import '../ui/widgets/aprs_symbol_widget.dart';
import '../ui/widgets/callsign_field.dart';
import '../theme/meridian_colors.dart';
import '../theme/theme_controller.dart';

/// Application settings screen.
///
/// The Appearance section (theme mode selection) is fully functional.
/// All other sections are stubbed — they display the correct structure but
/// do not yet wire up to persisted preferences or service config.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sections = [
      const _AppearanceSection(),
      const _AppColorSection(),
      const _MyStationSection(),
      const _BeaconingSection(),
      const _ConnectionSection(),
      const _HistorySection(),
      const _MapSection(),
      const _DisplaySection(),
      const _NotificationsSection(),
      const _AccountSection(),
      const _AboutSection(),
      const _AcknowledgementsSection(),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView.separated(
        itemCount: sections.length,
        separatorBuilder: (context, index) =>
            const Divider(indent: 16, endIndent: 16),
        itemBuilder: (context, index) => sections[index],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header helper
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Appearance
// ---------------------------------------------------------------------------

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ThemeController>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('Appearance'),
        ListTile(
          title: const Text('Theme'),
          subtitle: const Text('Choose light, dark, or follow the system.'),
          trailing: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Symbols.light_mode),
                label: Text('Light'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Symbols.dark_mode),
                label: Text('Dark'),
              ),
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Symbols.brightness_auto),
                label: Text('Auto'),
              ),
            ],
            selected: {controller.themeMode},
            onSelectionChanged: (modes) {
              if (modes.isNotEmpty) {
                context.read<ThemeController>().setThemeMode(modes.first);
              }
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// App Color
// ---------------------------------------------------------------------------

/// Seed color picker shown on all platforms.
///
/// On Android 12+ a "System" swatch appears first — selecting it re-enables
/// wallpaper-derived dynamic color. On all other platforms (iOS, desktop,
/// Android 11 and below) only the fixed seed swatches are shown.
class _AppColorSection extends StatelessWidget {
  const _AppColorSection();

  static const _swatches = [
    (label: 'Meridian Blue', color: MeridianColors.primary),
    (label: 'Slate', color: Color(0xFF64748B)),
    (label: 'Violet', color: Color(0xFF7C3AED)),
    (label: 'Rose', color: Color(0xFFE11D48)),
    (label: 'Amber', color: Color(0xFFD97706)),
    (label: 'Teal', color: Color(0xFF0D9488)),
    (label: 'Emerald', color: Color(0xFF059669)),
    (label: 'Sky', color: Color(0xFF0284C7)),
  ];

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();

    final controller = context.watch<ThemeController>();
    final outline = Theme.of(context).colorScheme.outline;
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;

    final subtitle = controller.dynamicColorAvailable
        ? 'Tap a color to override wallpaper theming.'
        : 'Choose the app accent color.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('App Color'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  // "System" swatch — only on Android 12+ (dynamic color capable).
                  if (controller.dynamicColorAvailable)
                    _ColorSwatch(
                      label: 'System',
                      isSelected: controller.useDynamicColor,
                      outline: outline,
                      onTap: () =>
                          context.read<ThemeController>().setUseDynamicColor(),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: SweepGradient(
                            colors: [
                              Color(0xFFEF4444),
                              Color(0xFFF59E0B),
                              Color(0xFF10B981),
                              Color(0xFF2563EB),
                              Color(0xFF7C3AED),
                              Color(0xFFEF4444),
                            ],
                          ),
                        ),
                      ),
                    ),
                  // Fixed seed swatches.
                  ..._swatches.map((swatch) {
                    final isSelected =
                        !controller.useDynamicColor &&
                        controller.seedColor.toARGB32() ==
                            swatch.color.toARGB32();
                    return _ColorSwatch(
                      label: swatch.label,
                      isSelected: isSelected,
                      outline: outline,
                      onTap: () => context.read<ThemeController>().setSeedColor(
                        swatch.color,
                      ),
                      child: ColoredBox(color: swatch.color),
                    );
                  }),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A 44×44 tappable circle swatch used in [_AppColorSection].
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.label,
    required this.isSelected,
    required this.outline,
    required this.onTap,
    required this.child,
  });

  final String label;
  final bool isSelected;
  final Color outline;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      selected: isSelected,
      button: true,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ClipOval(child: SizedBox.expand(child: child)),
              if (isSelected)
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: outline, width: 2.5),
                  ),
                ),
              if (isSelected)
                Icon(
                  Symbols.check,
                  color: Theme.of(context).colorScheme.onPrimary,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// My Station
// ---------------------------------------------------------------------------

class _MyStationSection extends StatefulWidget {
  const _MyStationSection();

  @override
  State<_MyStationSection> createState() => _MyStationSectionState();
}

class _MyStationSectionState extends State<_MyStationSection> {
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('My Station'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: CallsignField(
            controller: _callsignCtrl,
            focusNode: _callsignFocus,
            label: 'Callsign',
            onChanged: (_) {}, // validation only; persist on focus loss
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
            maxLength: 43,
            onEditingComplete: () => FocusScope.of(context).unfocus(),
            onChanged: (v) => setState(() {}),
            buildCounter:
                (_, {required currentLength, required isFocused, maxLength}) {
                  return Text(
                    '$currentLength / ${maxLength ?? 43}',
                    style: Theme.of(context).textTheme.bodySmall,
                  );
                },
          ),
        ),
        const _SectionHeader('Position Source'),
        _LocationSourcePicker(latCtrl: _latCtrl, lonCtrl: _lonCtrl),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Symbol picker
// ---------------------------------------------------------------------------

/// A curated list of common APRS symbols with human-readable names.
class _AprsSymbolEntry {
  const _AprsSymbolEntry(this.table, this.code, this.name);

  final String table;
  final String code;
  final String name;
}

const _kAprsSymbols = <_AprsSymbolEntry>[
  _AprsSymbolEntry('/', '>', 'Car'),
  _AprsSymbolEntry('/', '-', 'House'),
  _AprsSymbolEntry('/', '[', 'Person / Runner'),
  _AprsSymbolEntry('/', '<', 'Motorcycle'),
  _AprsSymbolEntry('/', 'b', 'Bicycle'),
  _AprsSymbolEntry('/', 'k', 'Truck'),
  _AprsSymbolEntry('/', 'u', 'Semi Truck'),
  _AprsSymbolEntry('/', 'U', 'Bus'),
  _AprsSymbolEntry('/', 'j', 'Jeep'),
  _AprsSymbolEntry('/', 'v', 'Van'),
  _AprsSymbolEntry('/', 'X', 'Helicopter'),
  _AprsSymbolEntry('/', '^', 'Aircraft'),
  _AprsSymbolEntry('/', "'", 'Small Aircraft'),
  _AprsSymbolEntry('/', 'O', 'Balloon'),
  _AprsSymbolEntry('/', 'Y', 'Sailboat'),
  _AprsSymbolEntry('/', 's', 'Powerboat'),
  _AprsSymbolEntry('/', '_', 'Weather Station'),
  _AprsSymbolEntry('/', '#', 'Digipeater'),
  _AprsSymbolEntry('/', 'r', 'Repeater Tower'),
  _AprsSymbolEntry('/', 'a', 'Ambulance'),
  _AprsSymbolEntry('/', 'h', 'Hospital'),
  _AprsSymbolEntry('/', 'f', 'Fire Truck'),
  _AprsSymbolEntry('/', 'd', 'Fire Department'),
  _AprsSymbolEntry('/', 'P', 'Police'),
  _AprsSymbolEntry('/', '!', 'Emergency'),
  _AprsSymbolEntry('/', '+', 'Red Cross'),
  _AprsSymbolEntry('/', '@', 'Hurricane'),
  _AprsSymbolEntry('/', 'R', 'Recreational Vehicle'),
  _AprsSymbolEntry('/', 'n', 'Network Node'),
  _AprsSymbolEntry('/', '&', 'Gateway'),
  _AprsSymbolEntry('/', '\$', 'Phone'),
  _AprsSymbolEntry('\\', '-', 'House (overlay)'),
  _AprsSymbolEntry('\\', '>', 'Car (overlay)'),
  _AprsSymbolEntry('\\', '[', 'Person (overlay)'),
];

String _symbolName(String table, String code) {
  for (final s in _kAprsSymbols) {
    if (s.table == table && s.code == code) return s.name;
  }
  return 'Custom ($table$code)';
}

/// ListTile that shows the current symbol and opens a searchable picker dialog.
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
      subtitle: Text(_symbolName(symbolTable, symbolCode)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final result = await showDialog<_AprsSymbolEntry>(
          context: context,
          builder: (_) => _SymbolPickerDialog(
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

class _SymbolPickerDialog extends StatefulWidget {
  const _SymbolPickerDialog({
    required this.currentTable,
    required this.currentCode,
  });

  final String currentTable;
  final String currentCode;

  @override
  State<_SymbolPickerDialog> createState() => _SymbolPickerDialogState();
}

class _SymbolPickerDialogState extends State<_SymbolPickerDialog> {
  final _searchCtrl = TextEditingController();
  List<_AprsSymbolEntry> _filtered = _kAprsSymbols;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch(String query) {
    final q = query.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _kAprsSymbols
          : _kAprsSymbols
                .where((s) => s.name.toLowerCase().contains(q))
                .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Choose Symbol', style: theme.textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: _onSearch,
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 380),
            child: _filtered.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No symbols found.'),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _filtered.length,
                    itemBuilder: (context, index) {
                      final entry = _filtered[index];
                      final isSelected =
                          entry.table == widget.currentTable &&
                          entry.code == widget.currentCode;
                      return ListTile(
                        dense: true,
                        leading: AprsSymbolWidget(
                          symbolTable: entry.table,
                          symbolCode: entry.code,
                          size: 24,
                        ),
                        title: Text(entry.name),
                        subtitle: Text(
                          '${entry.table}${entry.code}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        selected: isSelected,
                        selectedTileColor: theme.colorScheme.primaryContainer
                            .withValues(alpha: 0.3),
                        onTap: () => Navigator.of(context).pop(entry),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Source picker: GPS (disabled with notice when unsupported) or Manual.
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

// ---------------------------------------------------------------------------
// Beaconing
// ---------------------------------------------------------------------------

class _BeaconingSection extends StatelessWidget {
  const _BeaconingSection();

  @override
  Widget build(BuildContext context) {
    final beaconing = context.watch<BeaconingService>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('Beaconing'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              const Text('Mode'),
              const SizedBox(width: 16),
              SegmentedButton<BeaconMode>(
                segments: const [
                  ButtonSegment(
                    value: BeaconMode.manual,
                    icon: Icon(Symbols.touch_app),
                    label: Text('Manual'),
                  ),
                  ButtonSegment(
                    value: BeaconMode.auto,
                    icon: Icon(Symbols.timer),
                    label: Text('Auto'),
                  ),
                  ButtonSegment(
                    value: BeaconMode.smart,
                    icon: Icon(Symbols.route),
                    label: Text('Smart'),
                  ),
                ],
                selected: {beaconing.mode},
                onSelectionChanged: (modes) {
                  if (modes.isNotEmpty) {
                    context.read<BeaconingService>().setMode(modes.first);
                  }
                },
              ),
            ],
          ),
        ),
        if (beaconing.mode == BeaconMode.auto) ...[
          _IntervalTile(
            intervalS: beaconing.autoIntervalS,
            onChanged: (v) =>
                context.read<BeaconingService>().setAutoInterval(v),
          ),
        ],
        if (beaconing.mode == BeaconMode.smart) ...[
          ListTile(
            title: const Text('SmartBeaconing™ Parameters'),
            subtitle: Text(
              'Fast ${beaconing.smartParams.fastSpeedKmh.toInt()} km/h → '
              '${beaconing.smartParams.fastRateS}s  •  '
              'Slow ${beaconing.smartParams.slowSpeedKmh.toInt()} km/h → '
              '${beaconing.smartParams.slowRateS}s',
            ),
            trailing: const Icon(Symbols.chevron_right),
            onTap: () => Navigator.push(
              context,
              buildPlatformRoute((_) => const _SmartBeaconingParamsScreen()),
            ),
          ),
        ],
        if (!kIsWeb && Platform.isIOS) const _IosBackgroundLocationPrompt(),
        if (!kIsWeb && Platform.isAndroid)
          Consumer<BackgroundServiceManager>(
            builder: (context, bsm, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  title: const Text('Background activity'),
                  subtitle: const Text(
                    'Keep beaconing active when the screen is locked.',
                  ),
                  value: bsm.backgroundActivityEnabled,
                  onChanged: (v) => context
                      .read<BackgroundServiceManager>()
                      .setBackgroundActivityEnabled(v),
                ),
                if (bsm.needsPermission && !bsm.isRunning)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        Icon(
                          Symbols.location_off,
                          size: 16,
                          color: MeridianColors.warning,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Background location permission needed to beacon '
                            'while the screen is locked.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: MeridianColors.warning),
                          ),
                        ),
                        TextButton(
                          onPressed: () => bsm.requestStartService(context),
                          child: const Text('Grant'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// iOS-only widget that watches [IosBackgroundService] and shows a
/// [CupertinoAlertDialog] when background location permission is needed.
/// Renders nothing visible; exists only to host the listener lifecycle.
class _IosBackgroundLocationPrompt extends StatefulWidget {
  const _IosBackgroundLocationPrompt();

  @override
  State<_IosBackgroundLocationPrompt> createState() =>
      _IosBackgroundLocationPromptState();
}

class _IosBackgroundLocationPromptState
    extends State<_IosBackgroundLocationPrompt> {
  late final IosBackgroundService _svc;

  @override
  void initState() {
    super.initState();
    _svc = context.read<IosBackgroundService>();
    _svc.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _svc.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (!mounted || !_svc.needsBackgroundLocationPrompt) return;
    _svc.clearBackgroundLocationPrompt();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showCupertinoDialog<void>(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: const Text('Background Location'),
          content: const Text(
            'To beacon your position while Meridian is in the background, '
            '"Always" location access is required. You can enable this in Settings.',
          ),
          actions: [
            CupertinoDialogAction(
              child: const Text('Not Now'),
              onPressed: () => Navigator.pop(context),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              child: const Text('Open Settings'),
              onPressed: () {
                Geolocator.openAppSettings();
                Navigator.pop(context);
              },
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _IntervalTile extends StatelessWidget {
  const _IntervalTile({required this.intervalS, required this.onChanged});

  final int intervalS;
  final ValueChanged<int> onChanged;

  static String _label(int minutes) =>
      minutes == 1 ? '1 minute' : '$minutes minutes';

  @override
  Widget build(BuildContext context) {
    // Snap any stored value to the nearest whole minute (1–60).
    final minutes = (intervalS / 60).round().clamp(1, 60);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: const Text('Beacon Interval'),
          subtitle: Text(_label(minutes)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Slider(
            min: 1,
            max: 60,
            divisions: 59,
            value: minutes.toDouble(),
            label: _label(minutes),
            onChanged: (v) => onChanged(v.round() * 60),
          ),
        ),
      ],
    );
  }
}

/// Sub-screen for SmartBeaconing™ parameter tuning.
class _SmartBeaconingParamsScreen extends StatefulWidget {
  const _SmartBeaconingParamsScreen();

  @override
  State<_SmartBeaconingParamsScreen> createState() =>
      _SmartBeaconingParamsScreenState();
}

class _SmartBeaconingParamsScreenState
    extends State<_SmartBeaconingParamsScreen> {
  late SmartBeaconingParams _params;

  @override
  void initState() {
    super.initState();
    _params = context.read<BeaconingService>().smartParams;
  }

  Future<void> _save() async {
    await context.read<BeaconingService>().setSmartParams(_params);
  }

  Future<void> _reset() async {
    await context.read<BeaconingService>().resetSmartDefaults();
    setState(() {
      _params = SmartBeaconingParams.defaults;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SmartBeaconing™ Parameters')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _paramRow(
            label: 'Fast Speed (km/h)',
            value: _params.fastSpeedKmh,
            min: 10,
            max: 200,
            onChanged: (v) {
              setState(() => _params = _params.copyWith(fastSpeedKmh: v));
              _save();
            },
          ),
          _paramRow(
            label: 'Fast Rate (seconds)',
            value: _params.fastRateS.toDouble(),
            min: 10,
            max: 600,
            onChanged: (v) {
              setState(() => _params = _params.copyWith(fastRateS: v.round()));
              _save();
            },
          ),
          _paramRow(
            label: 'Slow Speed (km/h)',
            value: _params.slowSpeedKmh,
            min: 1,
            max: 30,
            onChanged: (v) {
              setState(() => _params = _params.copyWith(slowSpeedKmh: v));
              _save();
            },
          ),
          _paramRow(
            label: 'Slow Rate (seconds)',
            value: _params.slowRateS.toDouble(),
            min: 60,
            max: 3600,
            onChanged: (v) {
              setState(() => _params = _params.copyWith(slowRateS: v.round()));
              _save();
            },
          ),
          _paramRow(
            label: 'Min Turn Time (seconds)',
            value: _params.minTurnTimeS.toDouble(),
            min: 5,
            max: 120,
            onChanged: (v) {
              setState(
                () => _params = _params.copyWith(minTurnTimeS: v.round()),
              );
              _save();
            },
          ),
          _paramRow(
            label: 'Min Turn Angle (degrees)',
            value: _params.minTurnAngleDeg,
            min: 5,
            max: 90,
            onChanged: (v) {
              setState(() => _params = _params.copyWith(minTurnAngleDeg: v));
              _save();
            },
          ),
          _paramRow(
            label: 'Turn Slope',
            value: _params.turnSlope,
            min: 10,
            max: 600,
            onChanged: (v) {
              setState(() => _params = _params.copyWith(turnSlope: v));
              _save();
            },
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            icon: const Icon(Symbols.refresh),
            label: const Text('Reset to Defaults'),
            onPressed: _reset,
          ),
        ],
      ),
    );
  }

  Widget _paramRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    final displayValue = value == value.truncateToDouble()
        ? '${value.toInt()}'
        : value.toStringAsFixed(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
              Text(
                displayValue,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
        Slider(
          min: min,
          max: max,
          value: value.clamp(min, max),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Connection
// ---------------------------------------------------------------------------

class _ConnectionSection extends StatelessWidget {
  const _ConnectionSection();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('Connection'),
        ListTile(
          title: Text('Default server'),
          subtitle: Text('rotate.aprs2.net:14580'),
          trailing: Icon(Symbols.chevron_right),
        ),
        ListTile(
          title: Text('Filter'),
          subtitle: Text('Range filter around current position'),
          trailing: Icon(Symbols.chevron_right),
        ),
      ],
    );
  }
}
// ---------------------------------------------------------------------------
// History
// ---------------------------------------------------------------------------

class _HistorySection extends StatelessWidget {
  const _HistorySection();

  // Day options: 0 is the sentinel for "forever".
  static const _dayOptions = [7, 14, 30, 90, 180, 365, 0];

  static String _label(int days) => days == 0 ? 'Forever' : '$days days';

  /// Snap [value] to the nearest option (handles defaults that may not be
  /// in the list, e.g. after an app update changes defaults).
  static int _snap(int value) => _dayOptions.reduce(
    (a, b) => (a - value).abs() <= (b - value).abs() ? a : b,
  );

  Widget _dayDropdown({
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return DropdownButton<int>(
      value: _snap(value),
      underline: const SizedBox.shrink(),
      items: _dayOptions
          .map((d) => DropdownMenuItem(value: d, child: Text(_label(d))))
          .toList(),
      onChanged: (d) {
        if (d != null) onChanged(d);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final stations = context.watch<StationService>();
    final messages = context.watch<MessageService>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('History'),

        // Packet log retention
        ListTile(
          title: const Text('Packet log'),
          subtitle: const Text('How long to keep received packets.'),
          trailing: _dayDropdown(
            value: stations.packetHistoryDays,
            onChanged: stations.setPacketHistoryDays,
          ),
        ),

        // Station history retention
        ListTile(
          title: const Text('Station history'),
          subtitle: const Text('How long to remember heard stations.'),
          trailing: _dayDropdown(
            value: stations.stationHistoryDays,
            onChanged: stations.setStationHistoryDays,
          ),
        ),

        // Message history retention
        ListTile(
          title: const Text('Message history'),
          subtitle: const Text('How long to keep sent and received messages.'),
          trailing: _dayDropdown(
            value: messages.messageHistoryDays,
            onChanged: messages.setMessageHistoryDays,
          ),
        ),

        // Clear actions
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Symbols.delete_sweep, size: 18),
                label: const Text('Clear packet log'),
                onPressed: () async {
                  await context.read<StationService>().clearPacketLog();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Packet log cleared')),
                    );
                  }
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Symbols.location_off, size: 18),
                label: const Text('Clear stations'),
                onPressed: () async {
                  await context.read<StationService>().clearStationHistory();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Station history cleared')),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Map
// ---------------------------------------------------------------------------

class _MapSection extends StatelessWidget {
  const _MapSection();

  static const _options = <({String label, int? value})>[
    (label: '15 min', value: 15),
    (label: '30 min', value: 30),
    (label: '1 hour', value: 60),
    (label: '2 hours', value: 120),
    (label: '6 hours', value: 360),
    (label: '12 hours', value: 720),
    (label: 'No limit', value: null),
  ];

  // Radius option values are always stored in km internally.
  static const _radiusOptionValues = [10, 25, 50, 100];

  static const _wxAgeOptions = <({String label, int value})>[
    (label: '15 min', value: 15),
    (label: '30 min', value: 30),
    (label: '1 hr', value: 60),
    (label: '2 hr', value: 120),
  ];

  static String _labelFor(int? value) => _options
      .firstWhere((o) => o.value == value, orElse: () => _options[2])
      .label;

  static String _radiusLabelFor(int km, {required bool imperial}) =>
      formatRadiusKm(
        _radiusOptionValues.contains(km) ? km : 50,
        imperial: imperial,
      );

  static String _wxAgeLabelFor(int value) => _wxAgeOptions
      .firstWhere((o) => o.value == value, orElse: () => _wxAgeOptions[2])
      .label;

  @override
  Widget build(BuildContext context) {
    final stations = context.watch<StationService>();
    final current = stations.stationMaxAgeMinutes;

    if (!kIsWeb && Platform.isIOS) {
      return _buildIos(context, stations, current);
    }
    return _buildMaterial(context, stations, current);
  }

  void _showRadiusDialog(
    BuildContext context,
    StationService stations, {
    required bool imperial,
  }) {
    showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('WX search radius'),
        children: _radiusOptionValues
            .map(
              (km) => SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(km),
                child: Text(
                  formatRadiusKm(km, imperial: imperial),
                  style: km == stations.weatherOverlayRadiusKm
                      ? TextStyle(
                          color: Theme.of(ctx).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        )
                      : null,
                ),
              ),
            )
            .toList(),
      ),
    ).then((v) {
      if (v != null) stations.setWeatherOverlayRadiusKm(v);
    });
  }

  void _showWxAgeDialog(BuildContext context, StationService stations) {
    showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('WX data max age'),
        children: _wxAgeOptions
            .map(
              (o) => SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(o.value),
                child: Text(
                  o.label,
                  style: o.value == stations.weatherOverlayMaxAgeMinutes
                      ? TextStyle(
                          color: Theme.of(ctx).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        )
                      : null,
                ),
              ),
            )
            .toList(),
      ),
    ).then((v) {
      if (v != null) stations.setWeatherOverlayMaxAgeMinutes(v);
    });
  }

  Widget _buildMaterial(
    BuildContext context,
    StationService stations,
    int? current,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('Map'),
        SwitchListTile.adaptive(
          title: const Text('Distance units'),
          subtitle: const Text('Use miles and feet instead of km and metres'),
          secondary: const Icon(Symbols.straighten),
          value: stations.useImperialUnits,
          onChanged: (v) => stations.setUseImperialUnits(v),
        ),
        ListTile(
          title: const Text('Station timeout'),
          subtitle: const Text('Hide stations not heard within this window.'),
          trailing: DropdownButton<int?>(
            value: current,
            underline: const SizedBox.shrink(),
            items: _options
                .map(
                  (o) => DropdownMenuItem<int?>(
                    value: o.value,
                    child: Text(o.label),
                  ),
                )
                .toList(),
            onChanged: (v) => stations.setStationMaxAgeMinutes(v),
          ),
        ),
        SwitchListTile.adaptive(
          title: const Text('Weather overlay'),
          subtitle: const Text('Show conditions from nearest WX station'),
          value: stations.showWeatherOverlay,
          onChanged: (v) => stations.setShowWeatherOverlay(v),
        ),
        if (stations.showWeatherOverlay) ...[
          ListTile(
            contentPadding: const EdgeInsets.only(left: 32, right: 16),
            title: const Text('Search radius'),
            subtitle: const Text('Maximum distance to nearest WX station'),
            trailing: Text(
              _radiusLabelFor(
                stations.weatherOverlayRadiusKm,
                imperial: stations.useImperialUnits,
              ),
            ),
            onTap: () => _showRadiusDialog(
              context,
              stations,
              imperial: stations.useImperialUnits,
            ),
          ),
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.only(left: 32, right: 16),
            title: const Text('Show in \u00b0C'),
            subtitle: const Text('Display temperature in Celsius'),
            value: stations.weatherOverlayUseCelsius,
            onChanged: (v) => stations.setWeatherOverlayUseCelsius(v),
          ),
          ListTile(
            contentPadding: const EdgeInsets.only(left: 32, right: 16),
            title: const Text('Data max age'),
            subtitle: const Text('Ignore WX reports older than this'),
            trailing: Text(
              _wxAgeLabelFor(stations.weatherOverlayMaxAgeMinutes),
            ),
            onTap: () => _showWxAgeDialog(context, stations),
          ),
        ],
      ],
    );
  }

  Widget _buildIos(
    BuildContext context,
    StationService stations,
    int? current,
  ) {
    final selectedIndex = _options
        .indexWhere((o) => o.value == current)
        .clamp(0, _options.length - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('Map'),
        SwitchListTile.adaptive(
          title: const Text('Distance units'),
          subtitle: const Text('Use miles and feet instead of km and metres'),
          secondary: const Icon(Symbols.straighten),
          value: stations.useImperialUnits,
          onChanged: (v) => stations.setUseImperialUnits(v),
        ),
        ListTile(
          title: const Text('Station timeout'),
          subtitle: const Text('Hide stations not heard within this window.'),
          trailing: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => showCupertinoModalPopup<void>(
              context: context,
              builder: (_) => SizedBox(
                height: 216,
                child: CupertinoPicker(
                  backgroundColor: CupertinoTheme.of(
                    context,
                  ).scaffoldBackgroundColor,
                  scrollController: FixedExtentScrollController(
                    initialItem: selectedIndex,
                  ),
                  itemExtent: 36,
                  onSelectedItemChanged: (i) =>
                      stations.setStationMaxAgeMinutes(_options[i].value),
                  children: _options.map((o) => Text(o.label)).toList(),
                ),
              ),
            ),
            child: Text(_labelFor(current)),
          ),
        ),
        SwitchListTile.adaptive(
          title: const Text('Weather overlay'),
          subtitle: const Text('Show conditions from nearest WX station'),
          value: stations.showWeatherOverlay,
          onChanged: (v) => stations.setShowWeatherOverlay(v),
        ),
        if (stations.showWeatherOverlay) ...[
          ListTile(
            contentPadding: const EdgeInsets.only(left: 32, right: 16),
            title: const Text('Search radius'),
            subtitle: const Text('Maximum distance to nearest WX station'),
            trailing: Text(
              _radiusLabelFor(
                stations.weatherOverlayRadiusKm,
                imperial: stations.useImperialUnits,
              ),
            ),
            onTap: () => _showRadiusDialog(
              context,
              stations,
              imperial: stations.useImperialUnits,
            ),
          ),
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.only(left: 32, right: 16),
            title: const Text('Show in \u00b0C'),
            subtitle: const Text('Display temperature in Celsius'),
            value: stations.weatherOverlayUseCelsius,
            onChanged: (v) => stations.setWeatherOverlayUseCelsius(v),
          ),
          ListTile(
            contentPadding: const EdgeInsets.only(left: 32, right: 16),
            title: const Text('Data max age'),
            subtitle: const Text('Ignore WX reports older than this'),
            trailing: Text(
              _wxAgeLabelFor(stations.weatherOverlayMaxAgeMinutes),
            ),
            onTap: () => _showWxAgeDialog(context, stations),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Display
// ---------------------------------------------------------------------------

class _DisplaySection extends StatelessWidget {
  const _DisplaySection();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('Display'),
        ListTile(
          title: Text('Station timeout'),
          subtitle: Text('Hide stations not heard for this long'),
          trailing: Icon(Symbols.chevron_right),
        ),
        ListTile(
          title: Text('Trail length'),
          subtitle: Text('Number of position points to show per station'),
          trailing: Icon(Symbols.chevron_right),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------------

class _NotificationsSection extends StatelessWidget {
  const _NotificationsSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('Notifications'),
        SwitchListTile.adaptive(
          title: const Text('Message alerts'),
          subtitle: const Text(
            'Notify when a message addressed to you arrives.',
          ),
          value: false,
          onChanged: null, // Stub — not yet functional.
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Account
// ---------------------------------------------------------------------------

class _AccountSection extends StatelessWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('Account'),
        ListTile(
          title: const Text('Sign in'),
          subtitle: const Text('Sign in to sync preferences across devices.'),
          trailing: Icon(
            Symbols.chevron_right,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          enabled: false, // Stub — backend not yet implemented.
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// About
// ---------------------------------------------------------------------------

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  static const _kVersion = '0.1.0';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('About'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Card.filled(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Symbols.wifi_tethering,
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Meridian APRS',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Version $_kVersion',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'APRS for the Modern Ham',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '© 2026 Eric Pasch  ·  GPL v3',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Symbols.code),
          title: const Text('GitHub'),
          subtitle: const Text('github.com/epasch/meridian-aprs'),
          trailing: const Icon(Symbols.open_in_new, size: 16),
          onTap: () => _launchUri(
            Uri.parse('https://github.com/epasch/meridian-aprs'),
            context,
          ),
        ),
        ListTile(
          leading: const Icon(Symbols.language),
          title: const Text('Website'),
          subtitle: const Text('meridianaprs.com'),
          trailing: const Icon(Symbols.open_in_new, size: 16),
          onTap: () =>
              _launchUri(Uri.parse('https://meridianaprs.com'), context),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Acknowledgements
// ---------------------------------------------------------------------------

class _AcknowledgementsSection extends StatelessWidget {
  const _AcknowledgementsSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('Acknowledgements'),
        ListTile(
          title: const Text('APRS Symbol Graphics'),
          subtitle: const Text(
            'aprs.fi symbol set by Heikki Hannikainen OH7LZB',
          ),
          trailing: const Icon(Symbols.open_in_new, size: 16),
          onTap: () => _launchUri(
            Uri.parse('https://github.com/hessu/aprs-symbols'),
            context,
          ),
        ),
        ListTile(
          title: const Text('Map Library'),
          subtitle: const Text('flutter_map by Luka S and contributors'),
          trailing: const Icon(Symbols.open_in_new, size: 16),
          onTap: () => _launchUri(
            Uri.parse('https://github.com/fleaflet/flutter_map'),
            context,
          ),
        ),
        ListTile(
          title: const Text('Map Data'),
          subtitle: const Text('© OpenStreetMap contributors'),
          trailing: const Icon(Symbols.open_in_new, size: 16),
          onTap: () => _launchUri(
            Uri.parse('https://www.openstreetmap.org/copyright'),
            context,
          ),
        ),
        ListTile(
          title: const Text('Map Tiles'),
          subtitle: const Text('Stadia Maps'),
          trailing: const Icon(Symbols.open_in_new, size: 16),
          onTap: () => _launchUri(Uri.parse('https://stadiamaps.com'), context),
        ),
        ListTile(
          title: const Text('Open Source Licenses'),
          trailing: const Icon(Symbols.chevron_right),
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'Meridian APRS',
            applicationVersion: _AboutSection._kVersion,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// URL launcher helper
// ---------------------------------------------------------------------------

Future<void> _launchUri(Uri uri, BuildContext context) async {
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open ${uri.host}')));
    }
  }
}
