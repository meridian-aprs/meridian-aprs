import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/transport/ble_constants.dart';

/// A known BLE-KISS TNC model — used by the scanner UI to render a friendly
/// label + icon for advertised devices.
///
/// The registry is purely cosmetic; it does not gate connection. Devices that
/// do not match any known entry still appear with their advertised name and a
/// generic Bluetooth icon.
@immutable
class BleTncKnownDevice {
  const BleTncKnownDevice({
    required this.displayName,
    required this.namePattern,
    required this.family,
    required this.icon,
  });

  /// Human-readable model name shown in the scanner list.
  final String displayName;

  /// Regex matched against the advertised platform name (case-insensitive).
  final RegExp namePattern;

  /// Which GATT family this device speaks.
  final BleKissFamily family;

  /// Icon shown alongside the model name.
  final IconData icon;

  /// All known devices, ordered roughly by likely user popularity.
  ///
  /// Add new entries here as we test new hardware. Patterns are
  /// case-insensitive and anchored to the start of the advertised name so
  /// "Mobilinkd TNC4 1234" matches `^Mobilinkd TNC4` while "Bob's Mobilinkd"
  /// does not.
  static final List<BleTncKnownDevice> all = [
    BleTncKnownDevice(
      displayName: 'Mobilinkd TNC4',
      namePattern: RegExp(r'^Mobilinkd\s*TNC4', caseSensitive: false),
      family: BleKissFamily.aprsSpecs,
      icon: Symbols.router,
    ),
    BleTncKnownDevice(
      displayName: 'Mobilinkd TNC3',
      namePattern: RegExp(r'^Mobilinkd\s*TNC3', caseSensitive: false),
      family: BleKissFamily.aprsSpecs,
      icon: Symbols.router,
    ),
    BleTncKnownDevice(
      displayName: 'PicoAPRS v4',
      namePattern: RegExp(r'^PicoAPRS', caseSensitive: false),
      family: BleKissFamily.aprsSpecs,
      icon: Symbols.router,
    ),
    BleTncKnownDevice(
      displayName: 'B.B. Link',
      namePattern: RegExp(
        r'^(B\.?B\.?[\s-]*Link|BBLink)',
        caseSensitive: false,
      ),
      family: BleKissFamily.aprsSpecs,
      icon: Symbols.cable,
    ),
    BleTncKnownDevice(
      displayName: 'BTECH UV-Pro',
      namePattern: RegExp(r'^(BTECH\s*)?UV[\s-]*PRO', caseSensitive: false),
      family: BleKissFamily.benshi,
      icon: Symbols.radio,
    ),
    BleTncKnownDevice(
      displayName: 'Vero VR-N76',
      namePattern: RegExp(r'^VR[\s-]*N76', caseSensitive: false),
      family: BleKissFamily.benshi,
      icon: Symbols.radio,
    ),
    BleTncKnownDevice(
      displayName: 'Vero VR-N7500',
      namePattern: RegExp(r'^VR[\s-]*N7500', caseSensitive: false),
      family: BleKissFamily.benshi,
      icon: Symbols.radio,
    ),
    BleTncKnownDevice(
      displayName: 'Radioddity GA-5WB',
      namePattern: RegExp(
        r'^(Radioddity\s*)?GA[\s-]*5WB',
        caseSensitive: false,
      ),
      family: BleKissFamily.benshi,
      icon: Symbols.radio,
    ),
    BleTncKnownDevice(
      displayName: 'RPC ESP32 APRS',
      namePattern: RegExp(
        r'^(RPC.*APRS|ESP32[\s-]*APRS)',
        caseSensitive: false,
      ),
      family: BleKissFamily.aprsSpecs,
      icon: Symbols.developer_board,
    ),
    BleTncKnownDevice(
      displayName: 'CA2RXU LoRa Tracker',
      namePattern: RegExp(r'^(LoRa[\s-]*Tracker|CA2RXU)', caseSensitive: false),
      family: BleKissFamily.aprsSpecs,
      icon: Symbols.developer_board,
    ),
  ];

  /// Look up the registry by advertised name. Returns `null` for devices that
  /// don't match any known pattern.
  static BleTncKnownDevice? matchByName(String? advertisedName) {
    if (advertisedName == null || advertisedName.isEmpty) return null;
    for (final entry in all) {
      if (entry.namePattern.hasMatch(advertisedName)) return entry;
    }
    return null;
  }
}
