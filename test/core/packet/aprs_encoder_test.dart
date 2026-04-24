import 'package:flutter_test/flutter_test.dart';

import 'package:meridian_aprs/core/packet/aprs_encoder.dart';

void main() {
  group('AprsEncoder.encodePosition', () {
    test('produces correct lat/lon format for N/W coordinates', () {
      final line = AprsEncoder.encodePosition(
        callsign: 'W1AW',
        ssid: 9,
        lat: 49.057_5, // 49°03.45'N
        lon: -72.029_1667, // 072°01.75'W
        symbolTable: '/',
        symbolCode: '>',
        comment: 'Test',
      );
      // Should contain source header
      expect(line, startsWith('W1AW-9>APMDN0,TCPIP*:='));
      // Lat: 49°03.45 → 4903.45N
      expect(line, contains('4903.'));
      expect(line, contains('N'));
      // Lon: 072°01.75 → 07201.75W
      expect(line, contains('07201.'));
      expect(line, contains('W'));
      // Symbol table appears right after lat, symbol code right after lon.
      // Layout: ...4903.xxN/07201.xxW>Comment
      expect(
        line,
        contains('N/07201.'),
      ); // symbol table '/' between lat and lon
      expect(line, contains('W>')); // symbol code '>' right after lon
      expect(line, contains('Test'));
    });

    test('uses = DTI (messaging-capable)', () {
      final line = AprsEncoder.encodePosition(
        callsign: 'K0ABC',
        ssid: 0,
        lat: 39.0,
        lon: -77.0,
        symbolTable: '/',
        symbolCode: '-',
      );
      expect(line, contains(':='));
    });

    test('omits SSID suffix when ssid is 0', () {
      final line = AprsEncoder.encodePosition(
        callsign: 'W1AW',
        ssid: 0,
        lat: 39.0,
        lon: -77.0,
        symbolTable: '/',
        symbolCode: '>',
      );
      expect(line, startsWith('W1AW>APMDN0'));
    });

    test('encodes S/E hemispheres correctly', () {
      final line = AprsEncoder.encodePosition(
        callsign: 'VK2ABC',
        ssid: 0,
        lat: -33.8688, // Sydney ~33°52.13'S
        lon: 151.2093, // ~151°12.56'E
        symbolTable: '/',
        symbolCode: '>',
      );
      expect(line, contains('S'));
      expect(line, contains('E'));
    });

    // M6: Coordinate range asserts
    test('assert fires for lat out of range', () {
      expect(
        () => AprsEncoder.encodePosition(
          callsign: 'W1AW',
          ssid: 0,
          lat: 91.0, // invalid
          lon: 0.0,
          symbolTable: '/',
          symbolCode: '>',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('assert fires for lon out of range', () {
      expect(
        () => AprsEncoder.encodePosition(
          callsign: 'W1AW',
          ssid: 0,
          lat: 0.0,
          lon: 181.0, // invalid
          symbolTable: '/',
          symbolCode: '>',
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('AprsEncoder.encodeMessage', () {
    test('includes TCPIP* path for APRS-IS', () {
      final line = AprsEncoder.encodeMessage(
        fromCallsign: 'W1AW',
        fromSsid: 9,
        toCallsign: 'WB4APR',
        text: 'Hello',
        messageId: '001',
      );
      expect(
        line,
        contains(',TCPIP*:'),
        reason: 'encodeMessage must include TCPIP* path for APRS-IS ingestion',
      );
    });

    test('pads addressee to 9 characters', () {
      final line = AprsEncoder.encodeMessage(
        fromCallsign: 'W1AW',
        fromSsid: 9,
        toCallsign: 'WB4APR',
        text: 'Hello',
        messageId: '001',
      );
      // Wire format: :WB4APR   :Hello{001
      expect(line, contains(':WB4APR   :'));
    });

    test('truncates long addressee to 9 characters', () {
      final line = AprsEncoder.encodeMessage(
        fromCallsign: 'W1AW',
        fromSsid: 0,
        toCallsign: 'TOOLONGCALL',
        text: 'Hi',
      );
      // Addressee field is always exactly 9 chars
      final colonIdx = line.lastIndexOf('::');
      if (colonIdx >= 0) {
        final addrField = line.substring(colonIdx + 2, colonIdx + 11);
        expect(addrField.length, equals(9));
      }
    });

    test('appends message ID when provided', () {
      final line = AprsEncoder.encodeMessage(
        fromCallsign: 'W1AW',
        fromSsid: 0,
        toCallsign: 'KD9ABC',
        text: 'Test',
        messageId: '042',
      );
      expect(line, endsWith('{042'));
    });

    test('omits message ID when null', () {
      final line = AprsEncoder.encodeMessage(
        fromCallsign: 'W1AW',
        fromSsid: 0,
        toCallsign: 'KD9ABC',
        text: 'No ID',
      );
      expect(line, isNot(contains('{')));
    });

    test('uppercases callsigns', () {
      final line = AprsEncoder.encodeMessage(
        fromCallsign: 'w1aw',
        fromSsid: 1,
        toCallsign: 'kb1xyz',
        text: 'Hi',
      );
      expect(line, startsWith('W1AW-1>'));
      expect(line, contains('KB1XYZ'));
    });
  });

  group('AprsEncoder.encodeAck', () {
    test('produces correct ACK format', () {
      final line = AprsEncoder.encodeAck(
        fromCallsign: 'W1AW',
        fromSsid: 9,
        toCallsign: 'WB4APR',
        messageId: '001',
      );
      expect(line, contains(':WB4APR   :ack001'));
    });

    test('includes TCPIP* path for APRS-IS', () {
      final line = AprsEncoder.encodeAck(
        fromCallsign: 'W1AW',
        fromSsid: 9,
        toCallsign: 'WB4APR',
        messageId: '001',
      );
      expect(
        line,
        contains(',TCPIP*:'),
        reason: 'encodeAck must include TCPIP* path for APRS-IS ingestion',
      );
    });
  });

  group('AprsEncoder.encodeRej', () {
    test('produces correct REJ format', () {
      final line = AprsEncoder.encodeRej(
        fromCallsign: 'W1AW',
        fromSsid: 0,
        toCallsign: 'WB4APR',
        messageId: '007',
      );
      expect(line, contains(':WB4APR   :rej007'));
    });

    test('includes TCPIP* path for APRS-IS', () {
      final line = AprsEncoder.encodeRej(
        fromCallsign: 'W1AW',
        fromSsid: 0,
        toCallsign: 'WB4APR',
        messageId: '007',
      );
      expect(
        line,
        contains(',TCPIP*:'),
        reason: 'encodeRej must include TCPIP* path for APRS-IS ingestion',
      );
    });
  });

  group('encodeBulletin (v0.17, ADR-057)', () {
    test('pads general BLN addressee to 9 chars and omits wire ID', () {
      final line = AprsEncoder.encodeBulletin(
        fromCallsign: 'W1ABC',
        fromSsid: 7,
        addressee: 'BLN0',
        body: 'Severe wx alert',
      );
      expect(line, contains('::BLN0     :Severe wx alert'));
      // No message-ID suffix.
      expect(line, isNot(contains('{')));
    });

    test('pads named-group addressee to 9 chars', () {
      final line = AprsEncoder.encodeBulletin(
        fromCallsign: 'W1ABC',
        fromSsid: 7,
        addressee: 'BLN1WX',
        body: 'Radar update',
      );
      expect(line, contains('::BLN1WX   :Radar update'));
    });

    test('uppercases the addressee', () {
      final line = AprsEncoder.encodeBulletin(
        fromCallsign: 'W1ABC',
        fromSsid: 0,
        addressee: 'bln1wx',
        body: 'foo',
      );
      expect(line, contains('::BLN1WX   :foo'));
    });

    test('source header respects SSID = 0 (no trailing -0)', () {
      final line = AprsEncoder.encodeBulletin(
        fromCallsign: 'W1ABC',
        fromSsid: 0,
        addressee: 'BLN0',
        body: 'test',
      );
      expect(line, startsWith('W1ABC>'));
      expect(line, isNot(contains('W1ABC-0>')));
    });

    test('includes TCPIP* path for APRS-IS', () {
      final line = AprsEncoder.encodeBulletin(
        fromCallsign: 'W1ABC',
        fromSsid: 7,
        addressee: 'BLN0',
        body: 'test',
      );
      expect(line, contains(',TCPIP*:'));
    });

    test('truncates oversize addressee to 9 chars', () {
      // BLN9TOOLONG = 11 chars; must truncate to 9.
      final line = AprsEncoder.encodeBulletin(
        fromCallsign: 'W1ABC',
        fromSsid: 0,
        addressee: 'BLN9TOOLONG',
        body: 'x',
      );
      expect(line, contains('::BLN9TOOLO:x'));
    });
  });

  group('encodeGroupMessage (v0.17, ADR-056)', () {
    test('pads group name to 9 chars and omits wire ID', () {
      final line = AprsEncoder.encodeGroupMessage(
        fromCallsign: 'W1ABC',
        fromSsid: 7,
        groupName: 'CQ',
        body: 'CQ CQ — anyone on freq?',
      );
      expect(line, contains('::CQ       :CQ CQ — anyone on freq?'));
      // No message-ID suffix — groups are never ACKed (ADR-055).
      expect(line, isNot(contains('{')));
    });

    test('pads longer names (CLUB) correctly', () {
      final line = AprsEncoder.encodeGroupMessage(
        fromCallsign: 'W1ABC',
        fromSsid: 7,
        groupName: 'CLUB',
        body: 'club chatter',
      );
      // CLUB is 4 chars → 5 trailing spaces to reach the 9-char pad.
      expect(line, contains('::CLUB     :club chatter'));
    });

    test('uppercases group name', () {
      final line = AprsEncoder.encodeGroupMessage(
        fromCallsign: 'W1ABC',
        fromSsid: 7,
        groupName: 'cq',
        body: 'x',
      );
      expect(line, contains('::CQ       :x'));
    });

    test('includes TCPIP* path', () {
      final line = AprsEncoder.encodeGroupMessage(
        fromCallsign: 'W1ABC',
        fromSsid: 0,
        groupName: 'QST',
        body: 'x',
      );
      expect(line, contains(',TCPIP*:'));
    });
  });
}
