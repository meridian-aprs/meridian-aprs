import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:meridian_aprs/core/transport/kiss_framer.dart';
import 'package:meridian_aprs/core/ax25/ax25_parser.dart';
import 'package:meridian_aprs/core/packet/aprs_parser.dart';
import 'package:meridian_aprs/core/packet/aprs_packet.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Encode a callsign + SSID into the 7-byte AX.25 address field format.
///
/// Each character byte is left-shifted by 1. The SSID byte encodes:
///   bits 4-1 — SSID (0–15)
///   bit 0    — extension bit (1 = last address in block)
List<int> encodeAddr(String callsign, int ssid, {bool last = false}) {
  final bytes = List<int>.filled(7, 0);
  final padded = callsign.padRight(6);
  for (int i = 0; i < 6; i++) {
    bytes[i] = padded.codeUnitAt(i) << 1;
  }
  bytes[6] = ((ssid & 0x0F) << 1) | (last ? 0x01 : 0x00);
  return bytes;
}

/// Build a complete KISS-wrapped AX.25 UI frame for the given parameters.
///
/// Encodes the full AX.25 address block (destination, source, digipeaters),
/// appends control (0x03) and PID (0xF0) bytes plus the APRS info field, then
/// wraps the result with [KissFramer.encode].
Uint8List buildKissFrame(
  String src,
  String dst,
  List<String> digis,
  String aprsInfo,
) {
  final addrBytes = <int>[];

  // Destination — never last (there is always at least a source after it).
  addrBytes.addAll(encodeAddr(dst, 0));

  // Source — last when there are no digipeaters.
  addrBytes.addAll(encodeAddr(src, 0, last: digis.isEmpty));

  // Digipeaters — last one carries the extension bit.
  for (int i = 0; i < digis.length; i++) {
    addrBytes.addAll(encodeAddr(digis[i], 0, last: i == digis.length - 1));
  }

  // Control (UI frame = 0x03), PID (no layer 3 = 0xF0), then info bytes.
  final frame = [...addrBytes, 0x03, 0xF0, ...aprsInfo.codeUnits];

  return KissFramer.encode(Uint8List.fromList(frame));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Serial KISS pipeline integration', () {
    late KissFramer framer;

    setUp(() {
      framer = KissFramer();
    });

    tearDown(() {
      framer.dispose();
    });

    test('decodes a position packet end-to-end from raw KISS bytes', () async {
      final kissBytes = buildKissFrame(
        'W1AW',
        'APRS',
        [],
        '!4903.50N/07201.75W-Test',
      );

      final frames = <Uint8List>[];
      final sub = framer.frames.listen(frames.add);
      framer.addBytes(kissBytes);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(frames, hasLength(1));

      final ax25Result = const Ax25Parser().parseFrame(frames[0]);
      expect(ax25Result, isA<Ax25Ok>());

      final packet = AprsParser().parseFrame(frames[0]);
      expect(packet, isA<PositionPacket>());

      final pos = packet as PositionPacket;
      expect(pos.source, equals('W1AW'));
      expect(pos.lat, closeTo(49.058, 0.01));
      expect(pos.lon, closeTo(-72.029, 0.01));
    });

    test('decodes a status packet end-to-end', () async {
      final kissBytes = buildKissFrame('KD9ABC', 'APRS', [], '>Net control');

      final frames = <Uint8List>[];
      final sub = framer.frames.listen(frames.add);
      framer.addBytes(kissBytes);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(frames, hasLength(1));

      final packet = AprsParser().parseFrame(frames[0]);
      expect(packet, isA<StatusPacket>());
      expect(packet.source, equals('KD9ABC'));
    });

    test(
      'produces UnknownPacket for valid KISS/AX.25 but invalid APRS info',
      () async {
        final kissBytes = buildKissFrame('W1AW', 'APRS', [], 'XXXXXXXXXX');

        final frames = <Uint8List>[];
        final sub = framer.frames.listen(frames.add);
        framer.addBytes(kissBytes);
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();

        expect(frames, hasLength(1));

        final packet = AprsParser().parseFrame(frames[0]);
        expect(packet, isA<UnknownPacket>());
      },
    );

    test('pipeline is robust to malformed KISS frame (missing FEND)', () async {
      // No FEND delimiters — framer must not emit any frame.
      final frames = <Uint8List>[];
      final sub = framer.frames.listen(frames.add);
      framer.addBytes([0x00, 0x41, 0x42, 0x43]);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(frames, isEmpty);
    });

    test('pipeline handles frame with digipeater path', () async {
      final kissBytes = buildKissFrame('W1AW', 'APRS', ['RELAY'], '>Hello');

      final frames = <Uint8List>[];
      final sub = framer.frames.listen(frames.add);
      framer.addBytes(kissBytes);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(frames, hasLength(1));

      final ax25Result = const Ax25Parser().parseFrame(frames[0]);
      expect(ax25Result, isA<Ax25Ok>());

      final frame = (ax25Result as Ax25Ok).frame;
      expect(frame.digipeaters, hasLength(1));
    });
  });
}
