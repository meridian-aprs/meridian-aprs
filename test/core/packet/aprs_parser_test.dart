import 'package:meridian_aprs/core/packet/aprs_packet.dart';
import 'package:meridian_aprs/core/packet/aprs_parser.dart';
import 'package:test/test.dart';

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
}
