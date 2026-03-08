import 'package:meridian_aprs/core/packet/position_parser.dart';
import 'package:meridian_aprs/core/packet/result.dart';
import 'package:meridian_aprs/core/packet/station.dart';
import 'package:meridian_aprs/core/packet/symbol_resolver.dart';
import 'package:test/test.dart';

void main() {
  group('APRS position parser', () {
    group('callsign parsing', () {
      test('parses bare callsign (no SSID)', () {
        const raw = 'N0CALL>APRS:!4903.50N/07201.75W-Test station';
        final result = parseAprsLine(raw);
        expect(result, isA<Ok<Station>>());
        expect((result as Ok<Station>).value.callsign, equals('N0CALL'));
      });

      test('parses callsign with SSID', () {
        const raw =
            'WB4APR-14>APWW10,TCPIP*,qAC,T2MCI:=3855.34N/07701.13W-Direwolf';
        final result = parseAprsLine(raw);
        expect(result, isA<Ok<Station>>());
        expect((result as Ok<Station>).value.callsign, equals('WB4APR-14'));
      });
    });

    group('position decoding', () {
      test('decodes lat/lon from ! position report', () {
        const raw = 'N0CALL>APRS:!4903.50N/07201.75W-Test';
        final station = (parseAprsLine(raw) as Ok<Station>).value;
        // 49°03.50' N = 49 + 3.50/60 = 49.0583...
        expect(station.lat, closeTo(49.0583, 0.001));
        // 072°01.75' W = -(72 + 1.75/60) = -72.0292...
        expect(station.lon, closeTo(-72.0292, 0.001));
      });

      test('decodes lat/lon from = position report', () {
        const raw =
            'WB4APR-14>APWW10,TCPIP*,qAC,T2MCI:=3855.34N/07701.13W-Direwolf';
        final station = (parseAprsLine(raw) as Ok<Station>).value;
        // 38°55.34' N = 38 + 55.34/60 = 38.9223...
        expect(station.lat, closeTo(38.9223, 0.001));
        // 077°01.13' W = -(77 + 1.13/60) = -77.0188...
        expect(station.lon, closeTo(-77.0188, 0.001));
      });

      test('decodes South latitude as negative', () {
        const raw = 'VK2TEST>APRS:!3351.00S/15112.00E-Sydney';
        final station = (parseAprsLine(raw) as Ok<Station>).value;
        expect(station.lat, closeTo(-33.85, 0.001));
        expect(station.lon, isPositive); // East
      });

      test('decodes lat/lon from / position-with-timestamp report', () {
        // DTI '/' + 7-char timestamp + position
        const raw = 'N0CALL>APRS:/221509z4903.50N/07201.75W-Test';
        final station = (parseAprsLine(raw) as Ok<Station>).value;
        expect(station.lat, closeTo(49.0583, 0.001));
        expect(station.lon, closeTo(-72.0292, 0.001));
      });

      test('decodes lat/lon from @ position-with-timestamp report', () {
        const raw = 'N0CALL>APRS:@221509z4903.50N/07201.75W-Test';
        final station = (parseAprsLine(raw) as Ok<Station>).value;
        expect(station.lat, closeTo(49.0583, 0.001));
        expect(station.lon, closeTo(-72.0292, 0.001));
      });

      test('preserves raw packet string', () {
        const raw = 'N0CALL>APRS:!4903.50N/07201.75W-Test';
        final station = (parseAprsLine(raw) as Ok<Station>).value;
        expect(station.rawPacket, equals(raw));
      });
    });

    group('symbol and comment extraction', () {
      test('extracts primary table symbol (/) and house code (-)', () {
        final station =
            (parseAprsLine('N0CALL>APRS:!4903.50N/07201.75W-Test station')
                    as Ok<Station>)
                .value;
        expect(station.symbolTable, equals('/'));
        expect(station.symbolCode, equals('-'));
        expect(station.comment, equals('Test station'));
      });

      test('extracts car symbol (/) and > code', () {
        final station =
            (parseAprsLine('N0CALL>APRS:!4903.50N/07201.75W>On the road')
                    as Ok<Station>)
                .value;
        expect(station.symbolTable, equals('/'));
        expect(station.symbolCode, equals('>'));
        expect(station.comment, equals('On the road'));
      });

      test(r'extracts alternate table (\) symbol', () {
        final station =
            (parseAprsLine(r'N0CALL>APRS:!4903.50N\07201.75W#Digipeater')
                    as Ok<Station>)
                .value;
        expect(station.symbolTable, equals(r'\'));
        expect(station.symbolCode, equals('#'));
        expect(station.comment, equals('Digipeater'));
      });

      test('comment is empty string when no comment', () {
        final station =
            (parseAprsLine('N0CALL>APRS:!4903.50N/07201.75W-') as Ok<Station>)
                .value;
        expect(station.comment, equals(''));
      });

      test('lastHeard is recent DateTime', () {
        final before = DateTime.now();
        final station =
            (parseAprsLine('N0CALL>APRS:!4903.50N/07201.75W-Test')
                    as Ok<Station>)
                .value;
        final after = DateTime.now();
        expect(
          station.lastHeard.isAfter(before) ||
              station.lastHeard.isAtSameMomentAs(before),
          isTrue,
        );
        expect(
          station.lastHeard.isBefore(after) ||
              station.lastHeard.isAtSameMomentAs(after),
          isTrue,
        );
      });
    });

    group('malformed packet handling (must not throw)', () {
      test('returns Err for completely malformed input', () {
        expect(parseAprsLine('BADPACKET'), isA<Err<Station>>());
      });

      test('returns Err for empty string', () {
        expect(parseAprsLine(''), isA<Err<Station>>());
      });

      test('returns Err for packet with no info field', () {
        expect(parseAprsLine('NOCALL>:'), isA<Err<Station>>());
      });

      test('returns Err for comment lines', () {
        expect(
          parseAprsLine('# logresp NOCALL unverified'),
          isA<Err<Station>>(),
        );
      });

      test('returns Err for non-position packet type (message)', () {
        expect(
          parseAprsLine('N0CALL>APRS::WB4APR   :Hello{001'),
          isA<Err<Station>>(),
        );
      });

      test('never throws for any malformed input', () {
        for (final s in ['', 'BADPACKET', 'NOCALL>:', ':::', 'a>b:']) {
          expect(() => parseAprsLine(s), returnsNormally);
        }
      });
    });
  });

  group('SymbolResolver', () {
    test('recognizes primary table house symbol', () {
      expect(SymbolResolver.isKnown('/', '-'), isTrue);
      expect(
        SymbolResolver.symbolName('/', '-'),
        equals('House / Home Station'),
      );
    });

    test('recognizes primary table car symbol', () {
      expect(SymbolResolver.isKnown('/', '>'), isTrue);
      expect(SymbolResolver.symbolName('/', '>'), equals('Car'));
    });

    test('returns Station for unknown symbol', () {
      expect(SymbolResolver.isKnown('/', '\x01'), isFalse);
      expect(SymbolResolver.symbolName('/', '\x01'), equals('Station'));
    });
  });
}
