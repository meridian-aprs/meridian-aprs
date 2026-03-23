import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:meridian_aprs/core/ax25/ax25_parser.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Encode a callsign + SSID into the 7-byte AX.25 address field format.
///
/// Each character byte is left-shifted by 1. The SSID byte encodes:
///   bit 5   — H-bit (has-been-repeated)
///   bits 4-1 — SSID (0–15)
///   bit 0   — extension bit (0 = more addresses follow, 1 = last address)
List<int> encodeAddr(
  String callsign,
  int ssid, {
  bool hBit = false,
  bool last = false,
}) {
  final bytes = List<int>.filled(7, 0);
  final padded = callsign.padRight(6); // pad / truncate to 6 chars
  for (int i = 0; i < 6; i++) {
    bytes[i] = padded.codeUnitAt(i) << 1;
  }
  bytes[6] = (hBit ? 0x20 : 0x00) | ((ssid & 0x0F) << 1) | (last ? 0x01 : 0x00);
  return bytes;
}

/// Build a minimal AX.25 UI frame as raw bytes.
///
/// Address order: destination, source, then digipeaters (if any).
/// The extension bit of the final address is set to 1 to mark end of block.
Uint8List buildFrame({
  required String dst,
  int dstSsid = 0,
  required String src,
  int srcSsid = 0,
  List<String> digis = const [],
  int control = 0x03,
  int pid = 0xF0,
  List<int> info = const [],
}) {
  final bytes = <int>[];

  // Build the ordered list as (callsign, ssid, isLast).
  final totalAddrs = 2 + digis.length;
  final addrs = <(String, int, bool)>[];
  addrs.add((dst, dstSsid, totalAddrs == 1)); // dst is only last if alone
  if (digis.isEmpty) {
    addrs.add((src, srcSsid, true)); // src is last when no digis
  } else {
    addrs.add((src, srcSsid, false));
    for (int i = 0; i < digis.length; i++) {
      addrs.add((digis[i], 0, i == digis.length - 1));
    }
  }

  for (final (cs, ssid, last) in addrs) {
    bytes.addAll(encodeAddr(cs, ssid, last: last));
  }

  bytes.add(control);
  bytes.add(pid);
  bytes.addAll(info);

  return Uint8List.fromList(bytes);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Ax25Parser', () {
    const parser = Ax25Parser();

    test('decodes a minimal 2-address frame (no digipeaters)', () {
      final raw = buildFrame(dst: 'APRS', src: 'W1AW', info: [0x21]);
      final result = parser.parseFrame(raw);

      expect(result, isA<Ax25Ok>());
      final frame = (result as Ax25Ok).frame;
      expect(frame.destination.callsign, equals('APRS'));
      expect(frame.source.callsign, equals('W1AW'));
      expect(frame.digipeaters, isEmpty);
      expect(frame.info, equals([0x21]));
    });

    test('decodes callsign with SSID', () {
      final raw = buildFrame(dst: 'APRS', src: 'W1AW', srcSsid: 9);
      final result = parser.parseFrame(raw);

      expect(result, isA<Ax25Ok>());
      final frame = (result as Ax25Ok).frame;
      expect(frame.source.ssid, equals(9));
      expect(frame.source.toString(), equals('W1AW-9'));
    });

    test('decodes frame with one digipeater', () {
      final raw = buildFrame(dst: 'APRS', src: 'W1AW', digis: ['RELAY']);
      final result = parser.parseFrame(raw);

      expect(result, isA<Ax25Ok>());
      final frame = (result as Ax25Ok).frame;
      expect(frame.digipeaters, hasLength(1));
      expect(frame.digipeaters[0].callsign, equals('RELAY'));
    });

    test('decodes frame with multiple digipeaters', () {
      final raw = buildFrame(
        dst: 'APRS',
        src: 'W1AW',
        digis: ['RELAY', 'WIDE1'],
      );
      final result = parser.parseFrame(raw);

      expect(result, isA<Ax25Ok>());
      final frame = (result as Ax25Ok).frame;
      expect(frame.digipeaters, hasLength(2));
      expect(frame.digipeaters[0].callsign, equals('RELAY'));
      expect(frame.digipeaters[1].callsign, equals('WIDE1'));
    });

    test('extracts info field', () {
      final raw = buildFrame(
        dst: 'APRS',
        src: 'W1AW',
        info: [0x21, 0x41, 0x42],
      );
      final result = parser.parseFrame(raw);

      expect(result, isA<Ax25Ok>());
      final frame = (result as Ax25Ok).frame;
      expect(frame.info, equals([0x21, 0x41, 0x42]));
    });

    test('returns Ax25Err for frame shorter than 16 bytes', () {
      final result = parser.parseFrame(Uint8List.fromList([0x01, 0x02]));
      expect(result, isA<Ax25Err>());
    });

    test('returns Ax25Err for truncated address block', () {
      // One 7-byte address field + control + PID = 9 bytes total.
      // The parser needs at least 2 addresses (14 bytes) plus control+PID.
      // However the minimum 16-byte check passes (>= 16 here we make it fail
      // by building a deliberately short but >= 16 byte buffer where the
      // address block doesn't contain a complete second address).
      //
      // Strategy: provide exactly 16 bytes consisting of one valid address
      // (7 bytes, extension bit set — marks last address) + 9 padding bytes.
      // The extension bit on the first address tells the parser the address
      // block is done after just one address, which should return Ax25Err
      // ("fewer than 2 addresses").
      final singleAddr = encodeAddr('W1AW', 0, last: true); // extension bit set
      final bytes = Uint8List.fromList([
        ...singleAddr, // 7 bytes, last=true → parser stops here
        0x03, 0xF0, // control + PID
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // padding to reach 16
      ]);
      expect(bytes.length, greaterThanOrEqualTo(16));
      final result = parser.parseFrame(bytes);
      expect(result, isA<Ax25Err>());
    });

    test('trims trailing spaces from callsign', () {
      // 'W1AW' padded to 6 chars is 'W1AW  ' — parser must trim.
      final raw = buildFrame(dst: 'APRS', src: 'W1AW');
      final result = parser.parseFrame(raw);

      expect(result, isA<Ax25Ok>());
      final frame = (result as Ax25Ok).frame;
      expect(frame.source.callsign, equals('W1AW'));
      expect(frame.source.callsign, isNot(contains(' ')));
    });

    // -------------------------------------------------------------------------
    // M7: control/PID validation
    // -------------------------------------------------------------------------

    test('non-UI control byte (0x13) returns Ax25Err with descriptive reason', () {
      final raw = buildFrame(
        dst: 'APRS',
        src: 'W1AW',
        control: 0x13,
        pid: 0xF0,
        info: [0x21],
      );
      final result = parser.parseFrame(raw);
      expect(result, isA<Ax25Err>());
      expect(
        (result as Ax25Err).reason,
        contains('Not a UI/APRS frame'),
      );
    });

    test('non-APRS PID (0xCF) returns Ax25Err with descriptive reason', () {
      final raw = buildFrame(
        dst: 'APRS',
        src: 'W1AW',
        control: 0x03,
        pid: 0xCF,
        info: [0x21],
      );
      final result = parser.parseFrame(raw);
      expect(result, isA<Ax25Err>());
      expect(
        (result as Ax25Err).reason,
        contains('Not a UI/APRS frame'),
      );
    });
  });
}
