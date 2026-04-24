import 'package:flutter_test/flutter_test.dart';

import 'package:meridian_aprs/core/connection/aprs_is_filter_builder.dart';
import 'package:meridian_aprs/core/connection/aprs_is_filter_config.dart';
import 'package:meridian_aprs/core/connection/lat_lng_box.dart';

void main() {
  group('AprsIsFilterBuilder.buildFilterLine', () {
    const seattleBox = LatLngBox(
      north: 48.0,
      south: 47.0,
      east: -122.0,
      west: -123.0,
    );

    test('appends g/BLN0..9 unconditionally (ADR-058)', () {
      final line = AprsIsFilterBuilder.buildFilterLine(
        box: seattleBox,
        config: AprsIsFilterConfig.regional,
      );
      expect(
        line,
        endsWith('g/BLN0/BLN1/BLN2/BLN3/BLN4/BLN5/BLN6/BLN7/BLN8/BLN9\r\n'),
      );
    });

    test('produces no named-group clause when subscriptions empty', () {
      final line = AprsIsFilterBuilder.buildFilterLine(
        box: seattleBox,
        config: AprsIsFilterConfig.regional,
      );
      expect(line, isNot(contains('g/BLN*')));
    });

    test('appends g/BLN*NAME per enabled subscription (wildcard form)', () {
      final line = AprsIsFilterBuilder.buildFilterLine(
        box: seattleBox,
        config: AprsIsFilterConfig.regional,
        namedBulletinGroups: ['WX', 'EMERG'],
      );
      expect(line, contains('g/BLN*WX'));
      expect(line, contains('g/BLN*EMERG'));
    });

    test('deduplicates and uppercases named groups', () {
      final line = AprsIsFilterBuilder.buildFilterLine(
        box: seattleBox,
        config: AprsIsFilterConfig.regional,
        namedBulletinGroups: ['wx', 'WX', 'WX'],
      );
      final matches = 'g/BLN*WX'.allMatches(line);
      expect(matches.length, 1);
    });

    test('drops invalid named-group names (non-alphanumeric, >5 chars)', () {
      final line = AprsIsFilterBuilder.buildFilterLine(
        box: seattleBox,
        config: AprsIsFilterConfig.regional,
        namedBulletinGroups: ['WX', 'TOO_LONG!', 'SIXLEN'],
      );
      expect(line, contains('g/BLN*WX'));
      expect(line, isNot(contains('TOO_LONG')));
      expect(line, isNot(contains('SIXLEN')));
    });

    test('retains exact area clause format across pad/min-radius math', () {
      // Regional = 25% pad, 50 km min. 1° box centred on 47.5°N → padded
      // s=46.75, n=48.25, w=-123.25, e=-121.75. minHalf ≈ 0.4505° which
      // does not dominate at this box size.
      final line = AprsIsFilterBuilder.buildFilterLine(
        box: seattleBox,
        config: AprsIsFilterConfig.regional,
      );
      expect(line, startsWith('#filter a/48.25/-123.25/46.75/-121.75 '));
    });
  });

  group('AprsIsFilterBuilder.buildDefaultFilterLine', () {
    test('uses 167 km floor on half-extent even for Local preset', () {
      // Local = 25 km min. Floor at 167 km → half ≈ 1.505° → n ≈ 49.005,
      // s ≈ 45.995. After toStringAsFixed(2): 49.00 / 46.00 (floating-point
      // representation of 45.995 lands just above for Dart's default rounding).
      final line = AprsIsFilterBuilder.buildDefaultFilterLine(
        lat: 47.5,
        lon: -122.5,
        config: AprsIsFilterConfig.local,
      );
      expect(line, startsWith('#filter a/49.00/-124.00/46.00/-121.00 '));
    });

    test('includes g/BLN0..9 in the default path', () {
      final line = AprsIsFilterBuilder.buildDefaultFilterLine(
        lat: 47.5,
        lon: -122.5,
        config: AprsIsFilterConfig.regional,
      );
      expect(
        line,
        endsWith('g/BLN0/BLN1/BLN2/BLN3/BLN4/BLN5/BLN6/BLN7/BLN8/BLN9\r\n'),
      );
    });

    test('appends named groups in the default path too', () {
      final line = AprsIsFilterBuilder.buildDefaultFilterLine(
        lat: 47.5,
        lon: -122.5,
        config: AprsIsFilterConfig.regional,
        namedBulletinGroups: ['WX'],
      );
      expect(line, contains('g/BLN*WX'));
    });
  });
}
