import 'package:flutter_test/flutter_test.dart';

import 'package:meridian_aprs/core/ax25/ax25_encoder.dart';
import 'package:meridian_aprs/core/ax25/ax25_parser.dart';

void main() {
  group('Ax25Encoder.buildAprsFrame', () {
    test('sets destination to APMDN0', () {
      final frame = Ax25Encoder.buildAprsFrame(
        sourceCallsign: 'W1AW',
        sourceSsid: 9,
        infoField: '!3910.00N/07700.00W>',
      );
      expect(frame.destination.callsign, equals('APMDN0'));
      expect(frame.destination.ssid, equals(0));
    });

    test('sets source callsign and SSID', () {
      final frame = Ax25Encoder.buildAprsFrame(
        sourceCallsign: 'kb1xyz',
        sourceSsid: 3,
        infoField: '>Status',
      );
      expect(frame.source.callsign, equals('KB1XYZ'));
      expect(frame.source.ssid, equals(3));
    });

    test('default digipeaters are WIDE1-1 and WIDE2-1', () {
      final frame = Ax25Encoder.buildAprsFrame(
        sourceCallsign: 'W1AW',
        sourceSsid: 0,
        infoField: '!test',
      );
      expect(frame.digipeaters.length, equals(2));
      expect(frame.digipeaters[0].callsign, equals('WIDE1'));
      expect(frame.digipeaters[0].ssid, equals(1));
      expect(frame.digipeaters[1].callsign, equals('WIDE2'));
      expect(frame.digipeaters[1].ssid, equals(1));
    });

    test('stores info field as code units', () {
      const info = '!3910.00N/07700.00W>';
      final frame = Ax25Encoder.buildAprsFrame(
        sourceCallsign: 'W1AW',
        sourceSsid: 0,
        infoField: info,
      );
      expect(String.fromCharCodes(frame.info), equals(info));
    });

    test('control byte is 0x03 (UI frame)', () {
      final frame = Ax25Encoder.buildAprsFrame(
        sourceCallsign: 'W1AW',
        sourceSsid: 0,
        infoField: '!',
      );
      expect(frame.control, equals(0x03));
    });

    test('PID byte is 0xF0 (no layer 3)', () {
      final frame = Ax25Encoder.buildAprsFrame(
        sourceCallsign: 'W1AW',
        sourceSsid: 0,
        infoField: '!',
      );
      expect(frame.pid, equals(0xF0));
    });
  });

  group('Ax25Encoder.encodeUiFrame', () {
    test('produces byte sequence parseable by Ax25Parser round-trip', () {
      const sourceCallsign = 'W1AW';
      const sourceSsid = 9;
      const info = '!3910.00N/07700.00W>';

      final frame = Ax25Encoder.buildAprsFrame(
        sourceCallsign: sourceCallsign,
        sourceSsid: sourceSsid,
        infoField: info,
      );
      final bytes = Ax25Encoder.encodeUiFrame(frame);
      expect(bytes, isNotEmpty);

      // Round-trip: decode with Ax25Parser.
      final parser = Ax25Parser();
      final result = parser.parseFrame(bytes);
      switch (result) {
        case Ax25Ok(:final frame):
          expect(frame.source.callsign, equals(sourceCallsign));
          expect(frame.source.ssid, equals(sourceSsid));
          expect(frame.destination.callsign, equals('APMDN0'));
          expect(String.fromCharCodes(frame.info), equals(info));
        case Ax25Err(:final reason):
          fail('Expected Ax25Ok but got Ax25Err: $reason');
      }
    });

    test('end-of-address-list bit set on last address byte', () {
      final frame = Ax25Encoder.buildAprsFrame(
        sourceCallsign: 'W1AW',
        sourceSsid: 0,
        infoField: '!',
        digipeaterAliases: [], // no digipeaters → source is last address
      );
      final bytes = Ax25Encoder.encodeUiFrame(frame);
      // Source ends at byte index 13 (dest 7 bytes + source 7 bytes = 14 bytes)
      // The end-bit (LSB) of the last address SSID byte should be 1.
      final sourceSsidByte = bytes[13];
      expect(
        sourceSsidByte & 0x01,
        equals(1),
        reason: 'End-of-address-list bit must be 1 on last address',
      );
    });

    test('destination address bytes are correctly shifted', () {
      final frame = Ax25Encoder.buildAprsFrame(
        sourceCallsign: 'W1AW',
        sourceSsid: 0,
        infoField: '!',
        digipeaterAliases: [],
      );
      final bytes = Ax25Encoder.encodeUiFrame(frame);
      // First 6 bytes are the destination callsign shifted left.
      // Destination is APMDN0: 'A' = 0x41 → 0x82, 'P' = 0x50 → 0xA0,
      // 'M' = 0x4D → 0x9A, etc.
      expect(bytes[0], equals('A'.codeUnitAt(0) << 1));
      expect(bytes[1], equals('P'.codeUnitAt(0) << 1));
      expect(bytes[2], equals('M'.codeUnitAt(0) << 1));
    });

    // -------------------------------------------------------------------------
    // B2: C/H-bit correctness (AX.25 v2.2 §3.12.4)
    // -------------------------------------------------------------------------

    test('destination SSID byte has C-bit (bit 7) set', () {
      final frame = Ax25Encoder.buildAprsFrame(
        sourceCallsign: 'W1AW',
        sourceSsid: 0,
        infoField: '!',
        digipeaterAliases: [],
      );
      final bytes = Ax25Encoder.encodeUiFrame(frame);
      // Destination SSID byte is at index 6.
      final destSsidByte = bytes[6];
      expect(
        destSsidByte & 0x80,
        equals(0x80),
        reason: 'Destination C-bit (bit 7) must be 1 (command frame)',
      );
    });

    test('source SSID byte has C/H-bit (bit 7) clear', () {
      final frame = Ax25Encoder.buildAprsFrame(
        sourceCallsign: 'W1AW',
        sourceSsid: 0,
        infoField: '!',
        digipeaterAliases: [],
      );
      final bytes = Ax25Encoder.encodeUiFrame(frame);
      // Source SSID byte is at index 13.
      final srcSsidByte = bytes[13];
      expect(
        srcSsidByte & 0x80,
        equals(0),
        reason: 'Source H-bit (bit 7) must be 0 on a newly transmitted frame',
      );
    });

    test('digipeater SSID bytes have H-bit (bit 7) clear', () {
      // Two digipeaters: WIDE1-1 and WIDE2-1.
      final frame = Ax25Encoder.buildAprsFrame(
        sourceCallsign: 'W1AW',
        sourceSsid: 0,
        infoField: '!',
        // Uses the default ['WIDE1-1', 'WIDE2-1']
      );
      final bytes = Ax25Encoder.encodeUiFrame(frame);
      // Layout: dest(7) + src(7) + digi0(7) + digi1(7) = 28 address bytes.
      // Digi0 SSID byte at index 20; digi1 SSID byte at index 27.
      final digi0SsidByte = bytes[20];
      final digi1SsidByte = bytes[27];
      expect(
        digi0SsidByte & 0x80,
        equals(0),
        reason: 'Digipeater 0 H-bit (bit 7) must be 0 on a new frame',
      );
      expect(
        digi1SsidByte & 0x80,
        equals(0),
        reason: 'Digipeater 1 H-bit (bit 7) must be 0 on a new frame',
      );
    });
  });
}
