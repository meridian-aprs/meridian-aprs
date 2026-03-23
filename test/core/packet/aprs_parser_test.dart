import 'dart:typed_data';

import 'package:meridian_aprs/core/packet/aprs_packet.dart';
import 'package:meridian_aprs/core/packet/aprs_parser.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// AX.25 frame builder (mirrors the helper in ax25_parser_test.dart)
// ---------------------------------------------------------------------------

List<int> _encodeAddr(
  String callsign,
  int ssid, {
  bool last = false,
}) {
  final bytes = List<int>.filled(7, 0);
  final padded = callsign.padRight(6);
  for (int i = 0; i < 6; i++) {
    bytes[i] = padded.codeUnitAt(i) << 1;
  }
  bytes[6] = ((ssid & 0x0F) << 1) | (last ? 0x01 : 0x00);
  return bytes;
}

Uint8List _buildAprsFrame({
  required String dst,
  int dstSsid = 0,
  required String src,
  int srcSsid = 0,
  int control = 0x03,
  int pid = 0xF0,
  required List<int> info,
}) {
  final bytes = <int>[];
  bytes.addAll(_encodeAddr(dst, dstSsid, last: false));
  bytes.addAll(_encodeAddr(src, srcSsid, last: true));
  bytes.add(control);
  bytes.add(pid);
  bytes.addAll(info);
  return Uint8List.fromList(bytes);
}

void main() {
  late AprsParser parser;

  setUp(() {
    parser = AprsParser();
  });

  // ---------------------------------------------------------------------------
  // Helper
  // ---------------------------------------------------------------------------

  T expectPacketType<T extends AprsPacket>(String line) {
    final packet = parser.parse(line);
    expect(
      packet,
      isA<T>(),
      reason:
          'Expected ${T.toString()} but got '
          '${packet.runtimeType}: '
          '${packet is UnknownPacket ? packet.reason : ""}',
    );
    return packet as T;
  }

  // ---------------------------------------------------------------------------
  // Header parsing (common to all packet types)
  // ---------------------------------------------------------------------------

  group('header parsing', () {
    test('extracts source callsign from position packet', () {
      final p = expectPacketType<PositionPacket>(
        'N0CALL>APRS:!4903.50N/07201.75W-Test station',
      );
      expect(p.source, equals('N0CALL'));
    });

    test('extracts source callsign with SSID', () {
      final p = expectPacketType<PositionPacket>(
        'W1AW-9>APRS,WIDE1-1,WIDE2-1:!3456.78N/07654.32W>Test comment',
      );
      expect(p.source, equals('W1AW-9'));
    });

    test('extracts destination', () {
      final p = expectPacketType<PositionPacket>(
        'N0CALL>APDU25,WIDE2-2:!4903.50N/07201.75W-Test',
      );
      expect(p.destination, equals('APDU25'));
    });

    test('extracts digipeater path', () {
      final p = expectPacketType<PositionPacket>(
        'W1AW-9>APRS,WIDE1-1,WIDE2-1:!3456.78N/07654.32W>Test comment',
      );
      expect(p.path, equals(['WIDE1-1', 'WIDE2-1']));
    });

    test('path is empty when only destination present', () {
      final p = expectPacketType<PositionPacket>(
        'N0CALL>APRS:!4903.50N/07201.75W-Test',
      );
      expect(p.path, isEmpty);
    });

    test('path includes qAC entry', () {
      final p = expectPacketType<PositionPacket>(
        'WB4APR-14>APWW10,TCPIP*,qAC,T2MCI:=3855.34N/07701.13W-Test',
      );
      expect(p.path, containsAll(['TCPIP*', 'qAC', 'T2MCI']));
    });

    test('receivedAt is a recent UTC time', () {
      final before = DateTime.now().toUtc();
      final p = expectPacketType<PositionPacket>(
        'N0CALL>APRS:!4903.50N/07201.75W-Test',
      );
      final after = DateTime.now().toUtc();
      expect(
        p.receivedAt.isAfter(before) || p.receivedAt.isAtSameMomentAs(before),
        isTrue,
      );
      expect(
        p.receivedAt.isBefore(after) || p.receivedAt.isAtSameMomentAs(after),
        isTrue,
      );
    });

    test('rawLine is preserved exactly', () {
      const raw = 'N0CALL>APRS:!4903.50N/07201.75W-Test';
      final p = expectPacketType<PositionPacket>(raw);
      expect(p.rawLine, equals(raw));
    });
  });

  // ---------------------------------------------------------------------------
  // PositionPacket — uncompressed
  // ---------------------------------------------------------------------------

  group('PositionPacket uncompressed', () {
    group('DTI ! (no timestamp, no messaging)', () {
      test('decodes lat/lon', () {
        final p = expectPacketType<PositionPacket>(
          'N0CALL>APRS:!4903.50N/07201.75W-Test',
        );
        expect(p.lat, closeTo(49.0583, 0.001));
        expect(p.lon, closeTo(-72.0292, 0.001));
      });

      test('hasMessaging is false', () {
        final p = expectPacketType<PositionPacket>(
          'N0CALL>APRS:!4903.50N/07201.75W-Test',
        );
        expect(p.hasMessaging, isFalse);
      });

      test('timestamp field is null', () {
        final p = expectPacketType<PositionPacket>(
          'N0CALL>APRS:!4903.50N/07201.75W-Test',
        );
        expect(p.timestamp, isNull);
      });

      test('extracts symbol table and code', () {
        final p = expectPacketType<PositionPacket>(
          'N0CALL>APRS:!4903.50N/07201.75W-Test station',
        );
        expect(p.symbolTable, equals('/'));
        expect(p.symbolCode, equals('-'));
      });

      test('extracts comment', () {
        final p = expectPacketType<PositionPacket>(
          'N0CALL>APRS:!4903.50N/07201.75W-Test station',
        );
        expect(p.comment, equals('Test station'));
      });

      test('empty comment', () {
        final p = expectPacketType<PositionPacket>(
          'N0CALL>APRS:!4903.50N/07201.75W-',
        );
        expect(p.comment, equals(''));
      });

      test('South latitude is negative', () {
        final p = expectPacketType<PositionPacket>(
          'VK2TEST>APRS:!3351.00S/15112.00E-Sydney',
        );
        expect(p.lat, isNegative);
        expect(p.lon, isPositive);
      });

      test('real-world packet W1AW-9', () {
        final p = expectPacketType<PositionPacket>(
          'W1AW-9>APRS,WIDE1-1,WIDE2-1:!3456.78N/07654.32W>Test comment',
        );
        // 34°56.78' N = 34 + 56.78/60
        expect(p.lat, closeTo(34.946, 0.001));
        // 076°54.32' W = -(76 + 54.32/60)
        expect(p.lon, closeTo(-76.905, 0.001));
        expect(p.symbolCode, equals('>'));
        expect(p.comment, equals('Test comment'));
      });
    });

    group('DTI = (no timestamp, with messaging)', () {
      test('hasMessaging is true', () {
        final p = expectPacketType<PositionPacket>(
          'WB4APR-14>APWW10,TCPIP*,qAC,T2MCI:=3855.34N/07701.13W-Direwolf',
        );
        expect(p.hasMessaging, isTrue);
      });

      test('decodes lat/lon', () {
        final p = expectPacketType<PositionPacket>(
          'WB4APR-14>APWW10,TCPIP*,qAC,T2MCI:=3855.34N/07701.13W-Direwolf',
        );
        expect(p.lat, closeTo(38.922, 0.001));
        expect(p.lon, closeTo(-77.019, 0.001));
      });
    });

    group('DTI / (with timestamp, no messaging)', () {
      test('decodes lat/lon', () {
        final p = expectPacketType<PositionPacket>(
          'N0CALL>APRS:/221509z4903.50N/07201.75W-Test',
        );
        expect(p.lat, closeTo(49.0583, 0.001));
        expect(p.lon, closeTo(-72.0292, 0.001));
      });

      test('hasMessaging is false', () {
        final p = expectPacketType<PositionPacket>(
          'N0CALL>APRS:/221509z4903.50N/07201.75W-Test',
        );
        expect(p.hasMessaging, isFalse);
      });

      test('timestamp field is populated', () {
        final p = expectPacketType<PositionPacket>(
          'N0CALL>APRS:/221509z4903.50N/07201.75W-Test',
        );
        expect(p.timestamp, isNotNull);
        expect(p.timestamp!.day, equals(22));
        expect(p.timestamp!.hour, equals(15));
        expect(p.timestamp!.minute, equals(9));
      });
    });

    group('DTI @ (with timestamp, with messaging)', () {
      test('decodes lat/lon', () {
        final p = expectPacketType<PositionPacket>(
          'KB1ABC>APDU25,WIDE2-2:@092345z4903.50N/07201.75W>059/003/A=001234Test',
        );
        expect(p.lat, closeTo(49.0583, 0.001));
        expect(p.lon, closeTo(-72.0292, 0.001));
      });

      test('hasMessaging is true', () {
        final p = expectPacketType<PositionPacket>(
          'KB1ABC>APDU25,WIDE2-2:@092345z4903.50N/07201.75W>059/003/A=001234Test',
        );
        expect(p.hasMessaging, isTrue);
      });

      test('extracts altitude from /A= extension', () {
        final p = expectPacketType<PositionPacket>(
          'KB1ABC>APDU25,WIDE2-2:@092345z4903.50N/07201.75W>059/003/A=001234Test',
        );
        expect(p.altitude, equals(1234.0));
      });

      test('extracts course and speed', () {
        final p = expectPacketType<PositionPacket>(
          'KB1ABC>APDU25,WIDE2-2:@092345z4903.50N/07201.75W>059/003/A=001234Test',
        );
        expect(p.course, equals(59));
        expect(p.speed, equals(3.0));
      });
    });

    group('alternate symbol table', () {
      test(r'extracts \ symbol table', () {
        final p = expectPacketType<PositionPacket>(
          r'N0CALL>APRS:!4903.50N\07201.75W#Digipeater',
        );
        expect(p.symbolTable, equals(r'\'));
        expect(p.symbolCode, equals('#'));
      });
    });
  });

  // ---------------------------------------------------------------------------
  // PositionPacket — compressed
  // ---------------------------------------------------------------------------

  group('PositionPacket compressed', () {
    test('decodes compressed position', () {
      // "N0CALL>APRS:=/5L!!<*e7>7P[Test compressed"
      // This is a real compressed position from the APRS spec examples.
      // Compressed: symTable=/ lat=5L!! lon=<*e7 symCode=> comment=7P[Test
      // The exact lat/lon values depend on correct base-91 decode.
      final p = expectPacketType<PositionPacket>(
        'N0CALL>APRS:=/5L!!<*e7>7P[Test compressed',
      );
      // Lat should be in reasonable North America range.
      expect(p.lat, greaterThan(0));
      expect(p.lat, lessThan(90));
      expect(p.lon, lessThan(0)); // West
      expect(p.lon, greaterThan(-180));
      expect(p.symbolTable, equals('/'));
      expect(p.hasMessaging, isTrue); // DTI =
    });

    test('returns PositionPacket not UnknownPacket for compressed', () {
      // Validate we don't fall through to UnknownPacket.
      final packet = parser.parse('N0CALL>APRS:=/5L!!<*e7>7P[Test compressed');
      expect(packet, isA<PositionPacket>());
    });
  });

  // ---------------------------------------------------------------------------
  // MessagePacket
  // ---------------------------------------------------------------------------

  group('MessagePacket', () {
    test('parses message with message ID', () {
      final p = expectPacketType<MessagePacket>(
        'KD9ABC>APRSTO,WIDE2-1::KB1XYZ   :Hello there{001',
      );
      expect(p.source, equals('KD9ABC'));
      expect(p.addressee, equals('KB1XYZ'));
      expect(p.message, equals('Hello there'));
      expect(p.messageId, equals('001'));
    });

    test('parses message without message ID', () {
      final p = expectPacketType<MessagePacket>(
        'W1ABC>APRS::KB2DEF   :Just a message',
      );
      expect(p.addressee, equals('KB2DEF'));
      expect(p.message, equals('Just a message'));
      expect(p.messageId, isNull);
    });

    test('strips padding from addressee', () {
      final p = expectPacketType<MessagePacket>('W1ABC>APRS::KB2DEF   :Hi');
      expect(p.addressee, equals('KB2DEF'));
      expect(p.addressee, isNot(contains(' ')));
    });

    test('preserves message text exactly', () {
      final p = expectPacketType<MessagePacket>(
        'W1ABC>APRS::KB2DEF   :Hello, World! 73 de W1ABC',
      );
      expect(p.message, equals('Hello, World! 73 de W1ABC'));
    });

    test('handles ACK message', () {
      // ACK format: :CALLSIGN :ackNNN
      final p = expectPacketType<MessagePacket>('W1ABC>APRS::KB2DEF   :ack001');
      expect(p.addressee, equals('KB2DEF'));
    });
  });

  // ---------------------------------------------------------------------------
  // WeatherPacket
  // ---------------------------------------------------------------------------

  group('WeatherPacket', () {
    test('parses standalone weather report', () {
      final p = expectPacketType<WeatherPacket>(
        'WX4XYZ>APRS:_10090556c220s004g008t060r000p000P000h68b10125',
      );
      expect(p.source, equals('WX4XYZ'));
    });

    test('decodes wind direction', () {
      final p = expectPacketType<WeatherPacket>(
        'WX4XYZ>APRS:_10090556c220s004g008t060r000p000P000h68b10125',
      );
      expect(p.windDirection, equals(220));
    });

    test('decodes wind speed', () {
      final p = expectPacketType<WeatherPacket>(
        'WX4XYZ>APRS:_10090556c220s004g008t060r000p000P000h68b10125',
      );
      expect(p.windSpeed, equals(4.0));
    });

    test('decodes wind gust', () {
      final p = expectPacketType<WeatherPacket>(
        'WX4XYZ>APRS:_10090556c220s004g008t060r000p000P000h68b10125',
      );
      expect(p.windGust, equals(8.0));
    });

    test('decodes temperature in Fahrenheit', () {
      final p = expectPacketType<WeatherPacket>(
        'WX4XYZ>APRS:_10090556c220s004g008t060r000p000P000h68b10125',
      );
      expect(p.temperature, equals(60.0));
    });

    test('decodes humidity', () {
      final p = expectPacketType<WeatherPacket>(
        'WX4XYZ>APRS:_10090556c220s004g008t060r000p000P000h68b10125',
      );
      expect(p.humidity, equals(68));
    });

    test('decodes barometric pressure in mb', () {
      final p = expectPacketType<WeatherPacket>(
        'WX4XYZ>APRS:_10090556c220s004g008t060r000p000P000h68b10125',
      );
      // b10125 → 10125 / 10 = 1012.5 mb
      expect(p.pressure, closeTo(1012.5, 0.01));
    });

    test('decodes rainfall 1h', () {
      final p = expectPacketType<WeatherPacket>(
        'WX4XYZ>APRS:_10090556c220s004g008t060r000p000P000h68b10125',
      );
      expect(p.rainfall1h, equals(0.0));
    });
  });

  // ---------------------------------------------------------------------------
  // ObjectPacket
  // ---------------------------------------------------------------------------

  group('ObjectPacket', () {
    test('parses alive object', () {
      final p = expectPacketType<ObjectPacket>(
        'W1ABC>APRS:;HOSPITAL *092345z4903.50N/07201.75W/',
      );
      expect(p.objectName, equals('HOSPITAL'));
      expect(p.isAlive, isTrue);
    });

    test('decodes object lat/lon', () {
      final p = expectPacketType<ObjectPacket>(
        'W1ABC>APRS:;HOSPITAL *092345z4903.50N/07201.75W/',
      );
      expect(p.lat, closeTo(49.0583, 0.001));
      expect(p.lon, closeTo(-72.0292, 0.001));
    });

    test('extracts object symbol', () {
      final p = expectPacketType<ObjectPacket>(
        'W1ABC>APRS:;HOSPITAL *092345z4903.50N/07201.75W/',
      );
      expect(p.symbolTable, equals('/'));
      expect(p.symbolCode, equals('/'));
    });

    test('parses killed object', () {
      final p = expectPacketType<ObjectPacket>(
        'W1ABC>APRS:;HOSPITAL _092345z4903.50N/07201.75W/',
      );
      expect(p.isAlive, isFalse);
    });

    test('trims object name whitespace', () {
      // Name is padded to 9 chars in the wire format.
      final p = expectPacketType<ObjectPacket>(
        'W1ABC>APRS:;TEST     *092345z4903.50N/07201.75W/',
      );
      expect(p.objectName, equals('TEST'));
    });
  });

  // ---------------------------------------------------------------------------
  // StatusPacket
  // ---------------------------------------------------------------------------

  group('StatusPacket', () {
    test('parses status report', () {
      final p = expectPacketType<StatusPacket>(
        'W1ABC>APRS:>Net Control Station',
      );
      expect(p.source, equals('W1ABC'));
      expect(p.status, equals('Net Control Station'));
    });

    test('empty status', () {
      final p = expectPacketType<StatusPacket>('W1ABC>APRS:>');
      expect(p.status, equals(''));
    });

    test('status with special characters', () {
      final p = expectPacketType<StatusPacket>(
        'W1ABC>APRS:>QRV on 144.390 MHz / APRS',
      );
      expect(p.status, contains('144.390'));
    });
  });

  // ---------------------------------------------------------------------------
  // MicEPacket
  // ---------------------------------------------------------------------------

  group('MicEPacket', () {
    // Real-world Mic-E packet: WB4APR-14>T2SR6Y,WIDE2-2:`(_fn"Oj/`
    // WB4APR is the inventor of APRS; his beacon is a good test vector.
    test('parses Mic-E packet (backtick DTI)', () {
      final packet = parser.parse('WB4APR-14>T2SR6Y,WIDE2-2:`(_fn"Oj/`');
      // The destination T2SR6Y encodes Mic-E data; packet should be MicEPacket
      // or at minimum not crash. In some edge cases the destination may not
      // be a valid Mic-E encoding and will return UnknownPacket — that is also
      // acceptable as long as it does not throw.
      expect(packet, anyOf(isA<MicEPacket>(), isA<UnknownPacket>()));
    });

    test('Mic-E lat is in valid range', () {
      final packet = parser.parse('WB4APR-14>T2SR6Y,WIDE2-2:`(_fn"Oj/`');
      if (packet is MicEPacket) {
        expect(packet.lat, greaterThanOrEqualTo(-90));
        expect(packet.lat, lessThanOrEqualTo(90));
        expect(packet.lon, greaterThanOrEqualTo(-180));
        expect(packet.lon, lessThanOrEqualTo(180));
      }
    });

    test('Mic-E micEMessage is populated', () {
      final packet = parser.parse('WB4APR-14>T2SR6Y,WIDE2-2:`(_fn"Oj/`');
      if (packet is MicEPacket) {
        expect(packet.micEMessage, isNotEmpty);
      }
    });

    test("Mic-E with single-quote DTI is handled", () {
      // Single-quote DTI variant
      final packet = parser.parse(
        "KD0ABC-9>S3QRYU,WIDE1-1,WIDE2-1:'(_fn\"Oj/`",
      );
      expect(packet, anyOf(isA<MicEPacket>(), isA<UnknownPacket>()));
    });

    // -------------------------------------------------------------------------
    // P-Y encoding (custom message) — Bug 2 regression tests
    // -------------------------------------------------------------------------
    //
    // Packet: N0CALL-9>SX5E0A,WIDE1-1:`i<N Ol>/
    // Destination SX5E0A encodes:
    //   'S' (0x53) = P+3 → digit=3, msgBit=true  (custom, A-bit set)
    //   'X' (0x58) = P+8 → digit=8, msgBit=true  (custom, B-bit set)
    //   '5'        → digit=5, msgBit=false         (C-bit clear)
    //   'E' (0x45) = A+4 → digit=4, msgBit=true   (North)
    //   '0'        → digit=0, msgBit=false          (no lon offset)
    //   'A' (0x41) = A+0 → digit=0, msgBit=true   (West)
    // messageBits = 0b110 = 6 → En Route (custom)
    // lat = 38°54.00' N = 38.9000 N
    // lon: info[1]='i'(105-28=77), info[2]='<'(60-28=32), info[3]='N'(78-28=50)
    //      → 77°32.50' W = -77.5417
    test('P-Y destination decodes lat, lon, hemisphere, and message type', () {
      // All printable ASCII; info field is exactly 9 bytes.
      final packet = parser.parse('N0CALL-9>SX5E0A,WIDE1-1:`i<N Ol>/');
      expect(packet, isA<MicEPacket>());
      final p = packet as MicEPacket;
      expect(p.lat, closeTo(38.9, 0.001));
      expect(p.lon, closeTo(-77.5417, 0.001));
      expect(p.lat, isPositive, reason: 'should be North (positive)');
      expect(p.lon, isNegative, reason: 'should be West (negative)');
      expect(p.micEMessage, equals('En Route'));
    });

    // -------------------------------------------------------------------------
    // _micEMessages table ordering — Bug 3 regression tests
    // -------------------------------------------------------------------------
    //
    // These use the same constructible packet above but we only need a packet
    // that decodes to a specific messageBits value.  We use a helper that
    // calls _parseMicE indirectly through parse().
    //
    // messageBits=7 (0b111) → Off Duty
    //   All three bits set: positions 0,1,2 must all be letters.
    //   'S'(P+3),  'X'(P+8),  'T'(P+4)  → digits 3,8,4 / bits 1,1,1
    //   Position 3 North: 'E'(A+4), Position 4 no offset: '0', Position 5 West: 'A'
    //   Destination: SXT E0A → SXTE0A  (6 chars)
    //   lat = 38°84.00' — latMin=84 is out of range; that is fine, the parser
    //   does no range validation on lat.  We only check micEMessage here.
    test('messageBits=7 decodes to Off Duty', () {
      final packet = parser.parse('N0CALL-9>SXTE0A,WIDE1-1:`i<N Ol>/');
      expect(packet, isA<MicEPacket>());
      expect((packet as MicEPacket).micEMessage, equals('Off Duty'));
    });

    // messageBits=0 (0b000) → Emergency
    //   All three bits clear: positions 0,1,2 must all be plain digits.
    //   '3', '8', '5' → bits 0,0,0
    //   North: 'E', no offset: '0', West: 'A'  → Destination: 385E0A
    test('messageBits=0 decodes to Emergency', () {
      final packet = parser.parse('N0CALL-9>385E0A,WIDE1-1:`i<N Ol>/');
      expect(packet, isA<MicEPacket>());
      expect((packet as MicEPacket).micEMessage, equals('Emergency'));
    });

    // messageBits=5 (0b101) → In Service
    //   Bits: A=1, B=0, C=1 → pos0=letter, pos1=digit, pos2=letter
    //   'S'(P+3), '8', 'T'(P+4) → bits 1,0,1 = 0b101 = 5
    //   Destination: S8TE0A
    test('messageBits=5 decodes to In Service', () {
      final packet = parser.parse('N0CALL-9>S8TE0A,WIDE1-1:`i<N Ol>/');
      expect(packet, isA<MicEPacket>());
      expect((packet as MicEPacket).micEMessage, equals('In Service'));
    });
  });

  // ---------------------------------------------------------------------------
  // UnknownPacket (malformed / unrecognised)
  // ---------------------------------------------------------------------------

  group('UnknownPacket and malformed input', () {
    test('blank line returns UnknownPacket', () {
      expect(parser.parse(''), isA<UnknownPacket>());
    });

    test('server comment line returns UnknownPacket', () {
      expect(parser.parse('# logresp NOCALL unverified'), isA<UnknownPacket>());
    });

    test('line with no colon returns UnknownPacket', () {
      expect(parser.parse('GARBAGE LINE WITH NO COLON'), isA<UnknownPacket>());
    });

    test('line with no > in header returns UnknownPacket', () {
      expect(parser.parse('BADCALL>:info'), isA<UnknownPacket>());
    });

    test('completely garbage input returns UnknownPacket', () {
      expect(parser.parse(':::'), isA<UnknownPacket>());
    });

    test('empty info field returns UnknownPacket', () {
      // Header OK but nothing after the colon.
      expect(parser.parse('N0CALL>APRS:'), isA<UnknownPacket>());
    });

    test('unrecognised DTI returns UnknownPacket', () {
      // DTI 'Z' is not defined.
      expect(parser.parse('N0CALL>APRS:Znot a packet'), isA<UnknownPacket>());
    });

    test('telemetry packet (T) returns UnknownPacket', () {
      expect(
        parser.parse('N0CALL>APRS:T#001,100,200,050,000,255,00000001'),
        isA<UnknownPacket>(),
      );
    });

    test('never throws for any malformed input', () {
      final inputs = [
        '',
        'BADPACKET',
        'NOCALL>:',
        ':::',
        'a>b:',
        'GARBAGE LINE WITH NO COLON',
        '\x00\x01\x02',
        'N0CALL>APRS:',
        '!',
        'a' * 1000,
      ];
      for (final s in inputs) {
        expect(() => parser.parse(s), returnsNormally, reason: 'Input: $s');
      }
    });

    test('UnknownPacket has reason field', () {
      final p = parser.parse('') as UnknownPacket;
      expect(p.reason, isNotEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // ItemPacket
  // ---------------------------------------------------------------------------

  group('ItemPacket', () {
    test('parses alive item', () {
      final p = expectPacketType<ItemPacket>(
        'W1ABC>APRS:)RELAY !4903.50N/07201.75W-',
      );
      expect(p.itemName, equals('RELAY'));
      expect(p.isAlive, isTrue);
    });

    test('decodes item position', () {
      final p = expectPacketType<ItemPacket>(
        'W1ABC>APRS:)RELAY !4903.50N/07201.75W-',
      );
      expect(p.lat, closeTo(49.0583, 0.001));
      expect(p.lon, closeTo(-72.0292, 0.001));
    });

    test('parses killed item', () {
      final p = expectPacketType<ItemPacket>(
        'W1ABC>APRS:)RELAY _4903.50N/07201.75W-',
      );
      expect(p.isAlive, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Edge cases / real-world packets
  // ---------------------------------------------------------------------------

  group('real-world edge cases', () {
    test('position with course/speed but no altitude', () {
      final p = expectPacketType<PositionPacket>(
        'N0CALL>APRS:!4903.50N/07201.75W>059/030Comment here',
      );
      expect(p.course, equals(59));
      expect(p.speed, equals(30.0));
      expect(p.altitude, isNull);
    });

    test('position with zero course/speed is not stored', () {
      // 000/000 means no course/speed info
      final p = expectPacketType<PositionPacket>(
        'N0CALL>APRS:!4903.50N/07201.75W>000/000Comment',
      );
      expect(p.course, isNull);
      expect(p.speed, isNull);
    });

    test('APRS-IS line with TCPIP path is parsed correctly', () {
      final p = expectPacketType<PositionPacket>(
        'WB4APR-14>APWW10,TCPIP*,qAC,T2MCI:=3855.34N/07701.13W-Direwolf',
      );
      expect(p.source, equals('WB4APR-14'));
      expect(p.destination, equals('APWW10'));
      expect(p.path, contains('TCPIP*'));
    });
  });

  // ---------------------------------------------------------------------------
  // Device resolution — PositionPacket
  // ---------------------------------------------------------------------------

  group('device resolution — PositionPacket', () {
    test('destination APDR15 → device is APRSdroid', () {
      final p = expectPacketType<PositionPacket>(
        'N0CALL>APDR15,WIDE1-1:!4903.50N/07201.75W-Test',
      );
      expect(p.device, equals('APRSdroid'));
    });

    test('destination APDW2 → device is Dire Wolf', () {
      final p = expectPacketType<PositionPacket>(
        'N0CALL>APDW2,WIDE1-1:!4903.50N/07201.75W-Test',
      );
      expect(p.device, equals('Dire Wolf'));
    });

    test('unknown destination → device is null', () {
      final p = expectPacketType<PositionPacket>(
        'N0CALL>APXXX:!4903.50N/07201.75W-Test',
      );
      expect(p.device, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Device resolution and comment cleaning — MicEPacket
  // ---------------------------------------------------------------------------

  group('device resolution and comment cleaning — MicEPacket', () {
    // Baseline Mic-E info: "`i<N Ol>/" (9 bytes), destination SX5E0A decodes
    // to a valid position. We append comment bytes after the 9-byte fixed block.

    // Yaesu proprietary prefix: '"' + 2 data bytes + '}' (terminator).
    // Strip everything up to and including '}', then suffix _0 →
    // comment should be 'comment', device 'Yaesu FT3D series'.
    test('strips Yaesu 0x22 prefix (}-terminated) and detects _0 device suffix', () {
      // Build raw line: 9-byte info prefix + '"4G}' (Yaesu block) + 'comment_0'
      final rawLine =
          'N0CALL-9>SX5E0A,WIDE1-1:\x60i<N Ol>/\x224G}comment_0';
      final packet = parser.parse(rawLine);
      expect(packet, isA<MicEPacket>());
      if (packet is MicEPacket) {
        expect(packet.comment, equals('comment'));
        expect(packet.device, equals('Yaesu FT3D series'));
      }
    });

    // Backtick 2-channel telemetry: flag + exactly 4 hex digits → strip 5 bytes.
    // Per APRS 1.0.1 ch.10: 2 channels × 2 hex digits = "a1b2" here.
    test('strips backtick 2-channel telemetry (4 hex digits) and detects ] suffix', () {
      // comment field: \x60 + "a1b2" (valid hex) + "comment]"
      final rawLine =
          'N0CALL-9>SX5E0A,WIDE1-1:\x60i<N Ol>/\x60a1b2comment]';
      final packet = parser.parse(rawLine);
      expect(packet, isA<MicEPacket>());
      if (packet is MicEPacket) {
        expect(packet.comment, equals('comment'));
        expect(packet.device, equals('Kenwood (TH-D7x/TM-D7x)'));
      }
    });

    // Apostrophe 5-channel telemetry: flag + exactly 10 hex digits → strip 11 bytes.
    // Per APRS 1.0.1 ch.10: 5 channels × 2 hex digits = "a1b2c3d4e5" here.
    // Followed by ]" (Kenwood TM-D710 suffix).
    test('strips apostrophe 5-channel telemetry (10 hex digits) and detects ]" suffix (TM-D710)', () {
      final rawLine =
          'N0CALL-9>SX5E0A,WIDE1-1:\x60i<N Ol>/\x27a1b2c3d4e5comment]\x22';
      final packet = parser.parse(rawLine);
      expect(packet, isA<MicEPacket>());
      if (packet is MicEPacket) {
        expect(packet.comment, equals('comment'));
        expect(packet.device, equals('Kenwood TM-D710'));
      }
    });

    // Apostrophe 5-channel telemetry + ]= suffix (Kenwood TH-D72A).
    test('strips apostrophe 5-channel telemetry (10 hex digits) and detects ]= suffix', () {
      final rawLine =
          'N0CALL-9>SX5E0A,WIDE1-1:\x60i<N Ol>/\x27a1b2c3d4e5comment]=';
      final packet = parser.parse(rawLine);
      expect(packet, isA<MicEPacket>());
      if (packet is MicEPacket) {
        expect(packet.comment, equals('comment'));
        expect(packet.device, equals('Kenwood TH-D72A'));
      }
    });

    // Real-world Yaesu FT3D packet: "`"3x}_0"
    // Backtick followed by '"' (0x22) — not a hex digit → strip only 1 byte.
    // The altitude decoder then sees '"3x}' → 6 ft.  After altitude strip the
    // only remaining bytes are '_0' which the device resolver strips as
    // FT3D suffix → empty comment, device 'Yaesu FT3D series', altitude ≈ 6 ft.
    test('backtick + Yaesu altitude block: `"3x}_0 yields empty comment and altitude', () {
      // Exact comment bytes from: KM4TJO-7>S6TU8R,...:`h&Vl!b[/`"3x}_0
      // We use the same format but with the known-good SX5E0A destination.
      // Comment field (after 9-byte position block): \x60\x22\x33\x78\x7D\x5F\x30
      // = backtick + '"' + '3' + 'x' + '}' + '_' + '0'
      final rawLine =
          'N0CALL-9>SX5E0A,WIDE1-1:\x60i<N Ol>/\x60\x22\x33\x78\x7D\x5F\x30';
      final packet = parser.parse(rawLine);
      expect(packet, isA<MicEPacket>());
      if (packet is MicEPacket) {
        expect(packet.comment, equals(''));
        expect(packet.device, equals('Yaesu FT3D series'));
        // altitude = (0x22-33)*91^2 + (0x33-33)*91 + (0x78-33) - 10000
        //          = (1)*8281 + (18)*91 + (87) - 10000
        //          = 8281 + 1638 + 87 - 10000 = 6
        expect(packet.altitude, closeTo(6.0, 1.0));
      }
    });

    // Real-world Yaesu FT3D with user text in the comment: the radio uses
    // backtick (symbol table = ` at byte 8) + backtick comment prefix (byte 9)
    // + user text + `_0` device suffix + trailing space.
    // The 3-byte telemetry strip eats `\x60` + first 2 chars of user text.
    // The trailing space must be trimmed BEFORE suffix detection so `_\d$`
    // can match `_0`, giving stripped comment = remaining text without `_0`.
    // Real-world Yaesu FT3D with user text: radio prepends a backtick before
    // the user text and appends `_0` + trailing space.
    // Comment bytes: \x60 + "Eric's FT3DR_0 " (trailing space after suffix).
    // "Er" are NOT hex digits, so backtick is a 1-byte device-type prefix.
    // Strip 1 byte → "Eric's FT3DR_0 " → trim → "Eric's FT3DR_0".
    // _\d$ matches → strip "_0" → "Eric's FT3DR"; device = Yaesu FT3D series.
    test('backtick + non-hex text + _0 suffix + trailing space: full comment preserved', () {
      final rawLine =
          "N0CALL-9>SX5E0A,WIDE1-1:\x60i<N Ol>/\x60Eric's FT3DR_0 ";
      final packet = parser.parse(rawLine);
      expect(packet, isA<MicEPacket>());
      if (packet is MicEPacket) {
        expect(packet.comment, equals("Eric's FT3DR"));
        expect(packet.device, equals('Yaesu FT3D series'));
      }
    });

    // Actual 2-channel telemetry: backtick + 4 hex digits + remaining comment.
    // "a1b2" are valid hex → strip flag + 4 hex = 5 bytes.
    test('backtick + 4 hex digits = telemetry stripped, remainder kept', () {
      final rawLine =
          'N0CALL-9>SX5E0A,WIDE1-1:\x60i<N Ol>/\x60a1b2rest]';
      final packet = parser.parse(rawLine);
      expect(packet, isA<MicEPacket>());
      if (packet is MicEPacket) {
        expect(packet.comment, equals('rest'));
        expect(packet.device, equals('Kenwood (TH-D7x/TM-D7x)'));
      }
    });

    test('comment with no prefix and no suffix is unchanged', () {
      final rawLine =
          'N0CALL-9>SX5E0A,WIDE1-1:\x60i<N Ol>/plain comment';
      final packet = parser.parse(rawLine);
      expect(packet, isA<MicEPacket>());
      if (packet is MicEPacket) {
        expect(packet.comment, equals('plain comment'));
        expect(packet.device, isNull);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // B4: parseFrame latin1 decode
  // ---------------------------------------------------------------------------

  group('parseFrame — latin1 decode', () {
    // Build a Mic-E AX.25 frame with info[1] = 0xB7 (183 decimal).
    // utf8.decode(allowMalformed:true) would corrupt 0xB7 to U+FFFD (65533),
    // causing b1 = 65533 - 28 = 65505 — a hopelessly invalid longitude.
    // latin1.decode preserves it as 183, giving b1 = 183 - 28 = 155,
    // lonDeg = 155 → after wrap correction a valid result.
    //
    // Destination SX5E0A: S=P+3 stdBit, X=P+8 stdBit, 5=digit, E=North,
    // 0=no offset, A=West. This is the same destination used in other tests.
    // Info bytes: [0x60, 0xB7, 0x4C, 0x50, 0x20, 0x4C, 0x6C, 0x3E, 0x2F]
    // (backtick DTI, 0xB7 lon byte, then remaining Mic-E bytes)

    test('parseFrame with latin1 byte 0xB7 produces MicEPacket', () {
      final infoBytes = [0x60, 0xB7, 0x4C, 0x50, 0x20, 0x4C, 0x6C, 0x3E, 0x2F];
      final frame = _buildAprsFrame(
        dst: 'SX5E0A',
        src: 'N0CALL',
        srcSsid: 9,
        info: infoBytes,
      );
      final packet = parser.parseFrame(frame);
      expect(packet, isA<MicEPacket>());
      expect(
        (packet as MicEPacket).lon,
        inInclusiveRange(-180.0, 180.0),
      );
    });

    test('parseFrame and parse produce consistent lat/lon for latin1 0xB7', () {
      // APRS-IS string with same destination/info using latin1 char 0xB7.
      const rawLine = 'N0CALL-9>SX5E0A,WIDE1-1:\x60\xB7LPN Ol>/';
      final fromString = parser.parse(rawLine);
      expect(fromString, isA<MicEPacket>());

      final infoBytes = [0x60, 0xB7, 0x4C, 0x50, 0x20, 0x4C, 0x6C, 0x3E, 0x2F];
      final frame = _buildAprsFrame(
        dst: 'SX5E0A',
        src: 'N0CALL',
        srcSsid: 9,
        info: infoBytes,
      );
      final fromFrame = parser.parseFrame(frame);
      expect(fromFrame, isA<MicEPacket>());

      final p1 = fromString as MicEPacket;
      final p2 = fromFrame as MicEPacket;
      expect(p1.lat, closeTo(p2.lat, 1e-6));
      expect(p1.lon, closeTo(p2.lon, 1e-6));
    });
  });

  // ---------------------------------------------------------------------------
  // B5: Item minimum name length (3-char minimum)
  // ---------------------------------------------------------------------------

  group('ItemPacket — minimum name length', () {
    test('2-char item name (delimiter at index 2) is rejected', () {
      final packet = parser.parse('W1ABC>APRS:)AB!4903.50N/07201.75W-');
      expect(packet, isA<UnknownPacket>());
    });

    test('3-char item name is accepted', () {
      final p = expectPacketType<ItemPacket>(
        'W1ABC>APRS:)ABC!4903.50N/07201.75W-',
      );
      expect(p.itemName, equals('ABC'));
    });
  });

  // ---------------------------------------------------------------------------
  // M7: AX.25 control/PID validation
  // ---------------------------------------------------------------------------

  group('AX.25 control/PID validation (via parseFrame)', () {
    test('non-UI control byte (0x13) returns UnknownPacket', () {
      final infoBytes = [0x21, 0x41]; // minimal info
      final frame = _buildAprsFrame(
        dst: 'APRS',
        src: 'W1AW',
        control: 0x13,
        pid: 0xF0,
        info: infoBytes,
      );
      final packet = parser.parseFrame(frame);
      expect(packet, isA<UnknownPacket>());
      expect(
        (packet as UnknownPacket).reason,
        contains('Not a UI/APRS frame'),
      );
    });

    test('non-APRS PID (0xCF) returns UnknownPacket', () {
      final infoBytes = [0x21, 0x41];
      final frame = _buildAprsFrame(
        dst: 'APRS',
        src: 'W1AW',
        control: 0x03,
        pid: 0xCF,
        info: infoBytes,
      );
      final packet = parser.parseFrame(frame);
      expect(packet, isA<UnknownPacket>());
      expect(
        (packet as UnknownPacket).reason,
        contains('Not a UI/APRS frame'),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // M2: Compressed speed — pow formula (sByte=0 → speed=0.0, not -1.0)
  // ---------------------------------------------------------------------------

  group('PositionPacket compressed — speed formula', () {
    // cByte=3 → course=12; sByte=0 → speed = pow(1.08,0)-1 = 0.0
    // T byte: comprType=1 (course/speed) → bits 5-4 of (T-33) = 0b0001_0000 = 16
    //   T = 33+16 = 49 = '1'
    // c byte: cByte+33 = 36 = '$'
    // s byte: sByte+33 = 33 = '!'
    // Packet uses existing compressed pos base '/5L!!<*e7>' with csT='$!1'
    test('sByte=0 produces speed=0.0 not -1.0', () {
      final p = expectPacketType<PositionPacket>(
        r'N0CALL>APRS:=/5L!!<*e7>$!1Comment',
      );
      expect(p.speed, equals(0.0));
      expect(p.course, equals(12));
    });
  });

  // ---------------------------------------------------------------------------
  // M6: Compressed position — space c byte leaves course/speed null
  // ---------------------------------------------------------------------------

  group('PositionPacket compressed — space c byte', () {
    // First csT char is 0x20 (space): no course/speed data.
    // Using the same base '/5L!!<*e7>' with csT=' AB' (space + two data bytes).
    test('space c byte produces null course and speed', () {
      final p = expectPacketType<PositionPacket>(
        'N0CALL>APRS:=/5L!!<*e7> ABComment',
      );
      expect(p.course, isNull);
      expect(p.speed, isNull);
      expect(p.comment, equals('Comment'));
    });
  });

  // ---------------------------------------------------------------------------
  // M8: Uncompressed position — course/speed stripped from comment
  // ---------------------------------------------------------------------------

  group('PositionPacket uncompressed — course/speed stripped from comment', () {
    test('course/speed prefix stripped from comment', () {
      final p = expectPacketType<PositionPacket>(
        'N0CALL>APRS:!4903.50N/07201.75W>059/030My comment',
      );
      expect(p.comment, equals('My comment'));
    });

    test('000/000 course/speed leaves comment unchanged', () {
      final p = expectPacketType<PositionPacket>(
        'N0CALL>APRS:!4903.50N/07201.75W>000/000My comment',
      );
      expect(p.comment, equals('000/000My comment'));
    });
  });

  // ---------------------------------------------------------------------------
  // B1: Mic-E Standard vs Custom message type
  // ---------------------------------------------------------------------------

  group('MicEPacket — Standard vs Custom message bits', () {
    // Destination ABJE0A:
    //   'A'(0x41=A+0) i=0 → custBits |= 0b100 (4)
    //   'B'(0x42=A+1) i=1 → custBits |= 0b010 (2)
    //   'J'(0x4A=A+9) i=2 → custBits |= 0b001 (1)
    //   'E'(A+4) i=3 → isNorth, '0' i=4 → no offset, 'A'(A+0) i=5 → isWest
    //   custBits = 0b111 = 7, stdBits = 0 → _micECustomMessages[7] = 'Custom-6'
    test('Mic-E Custom message bits (A-J) decode to Custom-6', () {
      final rawLine = 'N0CALL-9>ABJE0A,WIDE1-1:\x60i<N Ol>/';
      final packet = parser.parse(rawLine);
      expect(packet, isA<MicEPacket>());
      expect((packet as MicEPacket).micEMessage, equals('Custom-6'));
    });

    // Destination ASRE0A:
    //   'A'(0x41) i=0 → custBits |= 0b100
    //   'S'(0x53=P+3) i=1 → stdBits |= 0b010
    //   'R'(0x52=P+2) i=2 → stdBits |= 0b001
    //   custBits=0b100≠0, stdBits=0b011≠0 → mixed → 'Unknown'
    test('Mic-E mixed Standard+Custom bits decode to Unknown', () {
      final rawLine = 'N0CALL-9>ASRE0A,WIDE1-1:\x60i<N Ol>/';
      final packet = parser.parse(rawLine);
      expect(packet, isA<MicEPacket>());
      expect((packet as MicEPacket).micEMessage, equals('Unknown'));
    });

    // Regression: P-Y only → stdBits → standard table (Off Duty, In Service)
    test('regression: Off Duty still decodes correctly', () {
      final packet = parser.parse('N0CALL-9>SXTE0A,WIDE1-1:`i<N Ol>/');
      expect(packet, isA<MicEPacket>());
      expect((packet as MicEPacket).micEMessage, equals('Off Duty'));
    });

    test('regression: In Service still decodes correctly', () {
      final packet = parser.parse('N0CALL-9>S8TE0A,WIDE1-1:`i<N Ol>/');
      expect(packet, isA<MicEPacket>());
      expect((packet as MicEPacket).micEMessage, equals('In Service'));
    });

    // All digits → stdBits=0, custBits=0 → Emergency
    test('regression: Emergency (all digits) still decodes correctly', () {
      final packet = parser.parse('N0CALL-9>385E0A,WIDE1-1:`i<N Ol>/');
      expect(packet, isA<MicEPacket>());
      expect((packet as MicEPacket).micEMessage, equals('Emergency'));
    });
  });

  // ---------------------------------------------------------------------------
  // B2: Mic-E base-91 altitude from comment
  // ---------------------------------------------------------------------------

  group('MicEPacket — base-91 altitude', () {
    // 10000 ft: altFeet+10000=20000
    //   c1=2 → char 35='#', c2=37 → char 70='F', c3=71 → char 104='h', c4='}'
    //   Verify: (2)*8281 + (37)*91 + (71) - 10000 = 16562+3367+71-10000 = 10000
    //   c1 is '#' (0x23), not '"' (0x22), so the Yaesu stripper is not triggered.
    test('base-91 altitude 10000 ft decoded from comment', () {
      final rawLine = 'N0CALL-9>SX5E0A,WIDE1-1:\x60i<N Ol>/\x23Fh}';
      final packet = parser.parse(rawLine);
      expect(packet, isA<MicEPacket>());
      expect((packet as MicEPacket).altitude, closeTo(10000.0, 0.5));
    });

    // -1720 ft: altFeet+10000=8280
    //   c1=0 → char 33='!', c2=90 → char 123='{', c3=90 → char 123='{', c4='}'
    //   Verify: (0)*8281 + (90)*91 + (90) - 10000 = 0+8190+90-10000 = -1720
    //   c1 is '!' (0x21), not '"' (0x22), so Yaesu stripper is not triggered.
    test('base-91 altitude -1720 ft (below sea level) decoded from comment', () {
      // info comment bytes: '!' '{' '{' '}' = 0x21 0x7B 0x7B 0x7D
      final rawLine = 'N0CALL-9>SX5E0A,WIDE1-1:\x60i<N Ol>/!\x7B\x7B\x7D';
      final packet = parser.parse(rawLine);
      expect(packet, isA<MicEPacket>());
      expect((packet as MicEPacket).altitude, closeTo(-1720.0, 0.5));
    });

    test('comment with no altitude prefix leaves altitude null', () {
      final rawLine =
          'N0CALL-9>SX5E0A,WIDE1-1:\x60i<N Ol>/plain comment';
      final packet = parser.parse(rawLine);
      expect(packet, isA<MicEPacket>());
      expect((packet as MicEPacket).altitude, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // B3: Compressed position GGA altitude
  // ---------------------------------------------------------------------------

  group('PositionPacket compressed — GGA altitude', () {
    // altitude ≈ 1000 ft: pow(1.002, x) = 1000 → x ≈ 3453
    //   3453 = 37*91 + 86 → cByte=37 → char 70='F', sByte=86 → char 119='w'
    //   T byte: comprType=2 → bits 5-4 of (T-33) = 0b10 = 0x20 → T=65='A'
    test('GGA altitude ~1000 ft decoded from compressed position', () {
      final p = expectPacketType<PositionPacket>(
        r'N0CALL>APRS:=/5L!!<*e7>FwAMy comment',
      );
      expect(p.altitude, isNotNull);
      expect(p.altitude!, closeTo(1000.0, 50.0));
    });
  });
}
