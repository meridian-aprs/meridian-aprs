/// AX.25 UI frame encoder.
///
/// Encodes [Ax25Frame] data models to raw AX.25 byte arrays suitable for
/// wrapping in a KISS frame and transmitting via [KissTncTransport.sendFrame].
/// Pure Dart — no platform imports.
library;

import 'dart:typed_data';

import 'ax25_frame.dart';
import '../packet/aprs_identity.dart';

/// Encodes AX.25 UI frames to byte arrays.
///
/// Usage:
/// ```dart
/// final frame = Ax25Encoder.buildAprsFrame(
///   sourceCallsign: 'W1AW',
///   sourceSsid: 9,
///   infoField: '!4903.50N/07201.75W>Comment',
/// );
/// final bytes = Ax25Encoder.encodeUiFrame(frame);
/// await transport.sendFrame(bytes); // KissFramer.encode() applied inside transport
/// ```
class Ax25Encoder {
  Ax25Encoder._();

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Builds an [Ax25Frame] for an APRS transmission.
  ///
  /// [infoField] is the raw APRS info string (everything after the `:`
  /// separator in an APRS-IS line, i.e. the DTI + data body).
  /// [digipeaterAliases] defaults to `['WIDE1-1', 'WIDE2-1']`.
  static Ax25Frame buildAprsFrame({
    required String sourceCallsign,
    required int sourceSsid,
    required String infoField,
    List<String> digipeaterAliases = const ['WIDE1-1', 'WIDE2-1'],
  }) {
    final digipeaters = digipeaterAliases.map((alias) {
      final parts = alias.split('-');
      final cs = parts[0];
      final ssid = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
      return Ax25Address(callsign: cs, ssid: ssid);
    }).toList();

    return Ax25Frame(
      destination: Ax25Address(callsign: AprsIdentity.tocall, ssid: 0),
      source: Ax25Address(
        callsign: sourceCallsign.toUpperCase(),
        ssid: sourceSsid,
      ),
      digipeaters: digipeaters,
      control: 0x03, // UI frame
      pid: 0xF0, // No layer 3
      info: infoField.codeUnits,
    );
  }

  /// Encodes an [Ax25Frame] to raw AX.25 bytes (no KISS wrapping).
  ///
  /// Wire format:
  /// ```
  /// [DEST addr 7 bytes][SRC addr 7 bytes][digi addr 7 bytes each]
  /// [control 1 byte][pid 1 byte][info N bytes]
  /// ```
  ///
  /// The end-of-address-list bit (LSB of the SSID byte) is set on the last
  /// address in the address field.
  static Uint8List encodeUiFrame(Ax25Frame frame) {
    final buf = <int>[];

    final allAddresses = [
      frame.destination,
      frame.source,
      ...frame.digipeaters,
    ];

    for (var i = 0; i < allAddresses.length; i++) {
      final addr = allAddresses[i];
      final isLast = i == allAddresses.length - 1;
      _encodeAddress(buf, addr, isLast: isLast, isDestination: i == 0);
    }

    buf.add(frame.control);
    buf.add(frame.pid);
    buf.addAll(frame.info);

    return Uint8List.fromList(buf);
  }

  // -------------------------------------------------------------------------
  // Internal
  // -------------------------------------------------------------------------

  /// Appends the 7-byte AX.25 address encoding for [addr] to [buf].
  ///
  /// AX.25 address field layout (7 bytes per address):
  /// - Bytes 0–5: ASCII callsign characters, each shifted left by 1 bit,
  ///   space-padded to 6 characters.
  /// - Byte 6 (SSID byte): `C/H|RR|SSID|END`
  ///   - bit 7 (C/H): C-bit = 1 for destination (command frame); H-bit = 0
  ///     for source and all digipeaters on a newly transmitted frame
  ///     (AX.25 v2.2 §3.12.4).
  ///   - bits 6–5 (RR): reserved, set to 1
  ///   - bits 4–1 (SSID): SSID value 0–15
  ///   - bit 0 (END): 1 if this is the last address in the list
  static void _encodeAddress(
    List<int> buf,
    Ax25Address addr, {
    required bool isLast,
    required bool isDestination,
  }) {
    // Pad or truncate callsign to 6 ASCII characters.
    final cs = addr.callsign.toUpperCase().padRight(6).substring(0, 6);
    for (final ch in cs.codeUnits) {
      buf.add((ch & 0xFF) << 1);
    }

    // SSID byte:
    //   bit 7: C-bit — 1 for destination (command), 0 for source and digis.
    //           Digipeater H-bit must also be 0 on a newly transmitted frame.
    //   bits 6–5: reserved, both set to 1
    //   bits 4–1: SSID nibble
    //   bit 0: end-of-address-list
    final cBit = isDestination ? 0x80 : 0x00;
    final reserved = 0x60; // bits 6 and 5 always 1
    final ssidBits = (addr.ssid & 0x0F) << 1;
    final endBit = isLast ? 0x01 : 0x00;
    buf.add(cBit | reserved | ssidBits | endBit);
  }
}
