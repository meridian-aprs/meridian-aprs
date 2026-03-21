import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/transport/tnc_config.dart';
import '../core/transport/tnc_preset.dart';
import '../services/tnc_service.dart';
import '../ui/theme/theme_provider.dart';

/// Application settings screen.
///
/// The Appearance section (theme mode selection) is fully functional.
/// All other sections are stubbed — they display the correct structure but
/// do not yet wire up to persisted preferences or service config.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView.separated(
        itemCount: 9,
        separatorBuilder: (context, index) =>
            const Divider(indent: 16, endIndent: 16),
        itemBuilder: (context, index) => [
          const _AppearanceSection(),
          const _MyStationSection(),
          const _BeaconingSection(),
          const _ConnectionSection(),
          const _TncSection(),
          const _DisplaySection(),
          const _NotificationsSection(),
          const _AccountSection(),
          const _AboutSection(),
        ][index],
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
    final themeProvider = context.watch<ThemeProvider>();

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
                icon: Icon(Icons.light_mode),
                label: Text('Light'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode),
                label: Text('Dark'),
              ),
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto),
                label: Text('Auto'),
              ),
            ],
            selected: {themeProvider.themeMode},
            onSelectionChanged: (modes) {
              if (modes.isNotEmpty) {
                context.read<ThemeProvider>().setThemeMode(modes.first);
              }
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// My Station
// ---------------------------------------------------------------------------

class _MyStationSection extends StatelessWidget {
  const _MyStationSection();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('My Station'),
        ListTile(title: Text('Callsign'), trailing: Icon(Icons.chevron_right)),
        ListTile(title: Text('SSID'), trailing: Icon(Icons.chevron_right)),
        ListTile(title: Text('Symbol'), trailing: Icon(Icons.chevron_right)),
        ListTile(title: Text('Comment'), trailing: Icon(Icons.chevron_right)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Beaconing
// ---------------------------------------------------------------------------

class _BeaconingSection extends StatelessWidget {
  const _BeaconingSection();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('Beaconing'),
        SwitchListTile(
          title: Text('Smart beaconing'),
          subtitle: Text(
            'Adjusts beacon rate based on speed and heading change.',
          ),
          value: false,
          onChanged: null, // Stub — not yet functional.
        ),
        ListTile(title: Text('Interval'), trailing: Icon(Icons.chevron_right)),
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
          trailing: Icon(Icons.chevron_right),
        ),
        ListTile(
          title: Text('Filter'),
          subtitle: Text('Range filter around current position'),
          trailing: Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// TNC
// ---------------------------------------------------------------------------

class _TncSection extends StatefulWidget {
  const _TncSection();

  @override
  State<_TncSection> createState() => _TncSectionState();
}

class _TncSectionState extends State<_TncSection> {
  static const List<int> _baudRates = [
    1200,
    2400,
    4800,
    9600,
    19200,
    38400,
    57600,
    115200,
  ];
  static const List<int> _dataBitsOptions = [7, 8];
  static const List<int> _stopBitsOptions = [1, 2];
  static const List<String> _parityOptions = ['none', 'odd', 'even'];

  late TncPreset _selectedPreset;
  String? _selectedPort;
  late int _baudRate;
  late int _dataBits;
  late int _stopBits;
  late String _parity;
  late bool _hwFlow;

  late final TextEditingController _txDelayController;
  late final TextEditingController _persistenceController;
  late final TextEditingController _slotTimeController;

  @override
  void initState() {
    super.initState();

    // Read initial values from TncService.activeConfig, or fall back to
    // Custom preset defaults.
    final config = context.read<TncService>().activeConfig;

    if (config != null) {
      final presetMatch = TncPreset.all.where((p) => p.id == config.presetId);
      _selectedPreset = presetMatch.isNotEmpty
          ? presetMatch.first
          : TncPreset.custom;
      _selectedPort = config.port;
      _baudRate = config.baudRate;
      _dataBits = config.dataBits;
      _stopBits = config.stopBits;
      _parity = config.parity;
      _hwFlow = config.hardwareFlowControl;
      _txDelayController = TextEditingController(
        text: '${config.kissTxDelayMs}',
      );
      _persistenceController = TextEditingController(
        text: '${config.kissPersistence}',
      );
      _slotTimeController = TextEditingController(
        text: '${config.kissSlotTimeMs}',
      );
    } else {
      _selectedPreset = TncPreset.custom;
      _selectedPort = null;
      _baudRate = TncPreset.custom.baudRate;
      _dataBits = TncPreset.custom.dataBits;
      _stopBits = TncPreset.custom.stopBits;
      _parity = TncPreset.custom.parity;
      _hwFlow = TncPreset.custom.hardwareFlowControl;
      _txDelayController = TextEditingController(text: '50');
      _persistenceController = TextEditingController(text: '63');
      _slotTimeController = TextEditingController(text: '10');
    }
  }

  @override
  void dispose() {
    _txDelayController.dispose();
    _persistenceController.dispose();
    _slotTimeController.dispose();
    super.dispose();
  }

  bool get _isCustom => _selectedPreset.id == TncPreset.customId;

  void _applyPreset(TncPreset preset) {
    setState(() {
      _selectedPreset = preset;
      if (preset.id != TncPreset.customId) {
        _baudRate = preset.baudRate;
        _dataBits = preset.dataBits;
        _stopBits = preset.stopBits;
        _parity = preset.parity;
        _hwFlow = preset.hardwareFlowControl;
      }
    });
  }

  Future<void> _save(TncService tncService) async {
    final port = _selectedPort ?? '';
    if (port.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a serial port before saving.')),
      );
      return;
    }

    final txDelay = int.tryParse(_txDelayController.text) ?? 50;
    final persistence = int.tryParse(_persistenceController.text) ?? 63;
    final slotTime = int.tryParse(_slotTimeController.text) ?? 10;

    final newConfig = TncConfig(
      port: port,
      baudRate: _baudRate,
      dataBits: _dataBits,
      stopBits: _stopBits,
      parity: _parity,
      hardwareFlowControl: _hwFlow,
      kissTxDelayMs: txDelay,
      kissPersistence: persistence,
      kissSlotTimeMs: slotTime,
      presetId: _isCustom ? null : _selectedPreset.id,
    );

    await tncService.updateConfig(newConfig);

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('TNC settings saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tncService = context.watch<TncService>();
    final theme = Theme.of(context);
    final ports = tncService.availablePorts();

    // Ensure the selected port is still valid after a refresh.
    if (_selectedPort != null &&
        ports.isNotEmpty &&
        !ports.contains(_selectedPort)) {
      _selectedPort = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('TNC'),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                leading: const Icon(Icons.settings_input_component),
                title: Text(
                  'TNC',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ---- Preset ----
                    _FieldLabel('Preset'),
                    DropdownButton<TncPreset>(
                      value: _selectedPreset,
                      isExpanded: true,
                      items: TncPreset.all
                          .map(
                            (p) => DropdownMenuItem(
                              value: p,
                              child: Text(p.displayName),
                            ),
                          )
                          .toList(),
                      onChanged: (preset) {
                        if (preset != null) _applyPreset(preset);
                      },
                    ),
                    const SizedBox(height: 12),

                    // ---- Port ----
                    _FieldLabel('Serial port'),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButton<String>(
                            value: ports.contains(_selectedPort)
                                ? _selectedPort
                                : null,
                            isExpanded: true,
                            hint: ports.isEmpty
                                ? const Text('No ports found')
                                : const Text('Select port'),
                            items: ports
                                .map(
                                  (p) => DropdownMenuItem(
                                    value: p,
                                    child: Text(p),
                                  ),
                                )
                                .toList(),
                            onChanged: (p) => setState(() => _selectedPort = p),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          tooltip: 'Refresh ports',
                          onPressed: () => setState(() {}),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ---- Baud rate ----
                    _FieldLabel('Baud rate'),
                    DropdownButton<int>(
                      value: _baudRate,
                      isExpanded: true,
                      items: _baudRates
                          .map(
                            (b) =>
                                DropdownMenuItem(value: b, child: Text('$b')),
                          )
                          .toList(),
                      onChanged: _isCustom
                          ? (b) {
                              if (b != null) setState(() => _baudRate = b);
                            }
                          : null,
                    ),
                    const SizedBox(height: 12),

                    // ---- Data bits ----
                    _FieldLabel('Data bits'),
                    DropdownButton<int>(
                      value: _dataBits,
                      isExpanded: true,
                      items: _dataBitsOptions
                          .map(
                            (d) =>
                                DropdownMenuItem(value: d, child: Text('$d')),
                          )
                          .toList(),
                      onChanged: _isCustom
                          ? (d) {
                              if (d != null) setState(() => _dataBits = d);
                            }
                          : null,
                    ),
                    const SizedBox(height: 12),

                    // ---- Stop bits ----
                    _FieldLabel('Stop bits'),
                    DropdownButton<int>(
                      value: _stopBits,
                      isExpanded: true,
                      items: _stopBitsOptions
                          .map(
                            (s) =>
                                DropdownMenuItem(value: s, child: Text('$s')),
                          )
                          .toList(),
                      onChanged: _isCustom
                          ? (s) {
                              if (s != null) setState(() => _stopBits = s);
                            }
                          : null,
                    ),
                    const SizedBox(height: 12),

                    // ---- Parity ----
                    _FieldLabel('Parity'),
                    DropdownButton<String>(
                      value: _parity,
                      isExpanded: true,
                      items: _parityOptions
                          .map(
                            (p) => DropdownMenuItem(value: p, child: Text(p)),
                          )
                          .toList(),
                      onChanged: _isCustom
                          ? (p) {
                              if (p != null) setState(() => _parity = p);
                            }
                          : null,
                    ),
                    const SizedBox(height: 4),

                    // ---- Hardware flow control ----
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Hardware flow control'),
                      value: _hwFlow,
                      onChanged: _isCustom
                          ? (v) => setState(() => _hwFlow = v)
                          : null,
                    ),
                    const SizedBox(height: 8),

                    // ---- Advanced KISS parameters ----
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Advanced KISS parameters'),
                      initiallyExpanded: false,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: TextFormField(
                            controller: _txDelayController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'TX delay (ms)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: TextFormField(
                            controller: _persistenceController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Persistence (0–255)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: TextFormField(
                            controller: _slotTimeController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Slot time (ms)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ---- Save button ----
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => _save(tncService),
                        child: const Text('Save'),
                      ),
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

/// Small label widget used above each dropdown in [_TncSectionState].
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
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
          trailing: Icon(Icons.chevron_right),
        ),
        ListTile(
          title: Text('Trail length'),
          subtitle: Text('Number of position points to show per station'),
          trailing: Icon(Icons.chevron_right),
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
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('Notifications'),
        SwitchListTile(
          title: Text('Message alerts'),
          subtitle: Text('Notify when a message addressed to you arrives.'),
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
            Icons.arrow_forward_ios,
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

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('About'),
        ListTile(title: Text('Version'), trailing: Text('0.1.0')),
        ListTile(
          title: Text('GitHub'),
          subtitle: Text('https://github.com/epasch/meridian-aprs'),
          trailing: Icon(Icons.open_in_new, size: 16),
        ),
      ],
    );
  }
}
