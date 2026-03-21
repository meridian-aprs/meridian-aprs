/// A bundled preset for a known TNC hardware device.
///
/// Presets define fixed serial parameters for known hardware so the user does
/// not need to configure baud rate, parity, etc. manually. Selecting a preset
/// other than [customId] locks the serial parameter fields in the UI.
class TncPreset {
  const TncPreset({
    required this.id,
    required this.displayName,
    required this.baudRate,
    this.dataBits = 8,
    this.stopBits = 1,
    this.parity = 'none',
    this.hardwareFlowControl = false,
    this.notes,
  });

  final String id;
  final String displayName;
  final int baudRate;
  final int dataBits;
  final int stopBits;

  /// Parity: 'none' | 'odd' | 'even'
  final String parity;
  final bool hardwareFlowControl;

  /// Optional user-facing notes shown in the UI.
  final String? notes;

  /// The sentinel ID for the user-defined Custom entry.
  static const String customId = 'custom';

  /// Mobilinkd TNC4 — USB CDC, 115200 baud, 8N1, no flow control.
  static const TncPreset mobilinkdTnc4 = TncPreset(
    id: 'mobilinkd_tnc4',
    displayName: 'Mobilinkd TNC4',
    baudRate: 115200,
    notes:
        'Connect via USB. No driver required on Linux or macOS.\n'
        'Linux: device appears as /dev/ttyUSB0 or /dev/ttyACM0.\n'
        'Windows: install the CP210x USB-to-UART driver from Silicon Labs if the port does not enumerate.',
  );

  /// Custom — user-defined parameters. Unlocks all serial parameter fields.
  static const TncPreset custom = TncPreset(
    id: customId,
    displayName: 'Custom',
    baudRate: 9600,
  );

  /// All bundled presets. Custom is always last.
  static const List<TncPreset> all = [mobilinkdTnc4, custom];
}
