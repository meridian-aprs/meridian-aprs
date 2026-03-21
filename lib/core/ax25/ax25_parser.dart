library;

import 'dart:typed_data';

import 'ax25_frame.dart';

/// Result of [Ax25Parser.parseFrame].
sealed class Ax25ParseResult {
  const Ax25ParseResult();
}

/// Successful AX.25 frame decode.
final class Ax25Ok extends Ax25ParseResult {
  const Ax25Ok(this.frame);
  final Ax25Frame frame;
}

/// AX.25 decode failure with a human-readable reason.
final class Ax25Err extends Ax25ParseResult {
  const Ax25Err(this.reason);
  final String reason;
}

/// Pure Dart AX.25 UI frame decoder.
///
/// Decodes raw AX.25 frame bytes (as extracted from a KISS frame) into an
/// [Ax25Frame]. Never throws — all malformed input returns [Ax25Err].
class Ax25Parser {
  const Ax25Parser();

  /// Decode raw AX.25 frame bytes into an [Ax25Frame].
  Ax25ParseResult parseFrame(Uint8List bytes) {
    if (bytes.length < 16) {
      return const Ax25Err('Frame too short (minimum 16 bytes)');
    }

    try {
      int offset = 0;
      final addresses = <Ax25Address>[];

      // Decode address block. Max 10 addresses as a safety cap.
      while (offset + 7 <= bytes.length && addresses.length < 10) {
        final addr = _decodeAddress(bytes, offset);
        addresses.add(addr);
        final extensionBit = bytes[offset + 6] & 0x01;
        offset += 7;
        if (extensionBit == 1) break; // last address
      }

      if (addresses.length < 2) {
        return const Ax25Err('Address block has fewer than 2 addresses');
      }

      if (offset + 2 > bytes.length) {
        return const Ax25Err('Frame too short for control and PID bytes');
      }

      final destination = addresses[0];
      final source = addresses[1];
      final digipeaters = addresses.length > 2
          ? addresses.sublist(2)
          : <Ax25Address>[];

      final control = bytes[offset];
      final pid = bytes[offset + 1];
      final info = bytes.sublist(offset + 2).toList();

      return Ax25Ok(
        Ax25Frame(
          destination: destination,
          source: source,
          digipeaters: digipeaters,
          control: control,
          pid: pid,
          info: info,
        ),
      );
    } catch (e) {
      return Ax25Err('Unexpected decode error: $e');
    }
  }

  /// Decode one 7-byte AX.25 address field starting at [offset].
  Ax25Address _decodeAddress(Uint8List bytes, int offset) {
    final charBytes = <int>[];
    for (int i = 0; i < 6; i++) {
      charBytes.add(bytes[offset + i] >> 1);
    }
    // Decode as ASCII, trim trailing spaces.
    final callsign = String.fromCharCodes(charBytes).trimRight();
    final ssidByte = bytes[offset + 6];
    final ssid = (ssidByte >> 1) & 0x0F;
    final hBit = ((ssidByte >> 5) & 0x01) == 1;
    return Ax25Address(callsign: callsign, ssid: ssid, hBit: hBit);
  }
}
