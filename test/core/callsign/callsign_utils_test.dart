import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_aprs/core/callsign/callsign_utils.dart';

void main() {
  group('stripSsid', () {
    test('no SSID returns callsign unchanged (uppercased)', () {
      expect(stripSsid('KM4TJO'), equals('KM4TJO'));
    });

    test('SSID -0 strips suffix', () {
      expect(stripSsid('KM4TJO-0'), equals('KM4TJO'));
    });

    test('numeric SSID -9 strips suffix', () {
      expect(stripSsid('KM4TJO-9'), equals('KM4TJO'));
    });

    test('two-digit numeric SSID -15 strips suffix', () {
      expect(stripSsid('KM4TJO-15'), equals('KM4TJO'));
    });

    test('D-STAR letter SSID -A strips suffix', () {
      expect(stripSsid('KM4TJO-A'), equals('KM4TJO'));
    });

    test('lowercase input is uppercased', () {
      expect(stripSsid('km4tjo-9'), equals('KM4TJO'));
    });
  });

  group('normalizeCallsign', () {
    test('-0 suffix is stripped', () {
      expect(normalizeCallsign('KM4TJO-0'), equals('KM4TJO'));
    });

    test('no SSID is returned unchanged', () {
      expect(normalizeCallsign('KM4TJO'), equals('KM4TJO'));
    });

    test('non-zero SSID is preserved', () {
      expect(normalizeCallsign('KM4TJO-9'), equals('KM4TJO-9'));
    });

    test('lowercase -0 is normalized', () {
      expect(normalizeCallsign('km4tjo-0'), equals('KM4TJO'));
    });

    test('lowercase no-SSID is uppercased', () {
      expect(normalizeCallsign('km4tjo'), equals('KM4TJO'));
    });
  });
}
