import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_aprs/core/transport/ble_constants.dart';
import 'package:meridian_aprs/ui/widgets/ble_tnc_known_device.dart';

void main() {
  group('BleTncKnownDevice.matchByName', () {
    test('returns null for null / empty input', () {
      expect(BleTncKnownDevice.matchByName(null), isNull);
      expect(BleTncKnownDevice.matchByName(''), isNull);
    });

    test('returns null for unknown / generic Bluetooth devices', () {
      expect(BleTncKnownDevice.matchByName("iPhone of Bob"), isNull);
      expect(BleTncKnownDevice.matchByName('AirPods Pro'), isNull);
      expect(BleTncKnownDevice.matchByName('Random ESP32'), isNull);
    });

    test('matches Mobilinkd TNC4 advertised names', () {
      final m = BleTncKnownDevice.matchByName('Mobilinkd TNC4 ABCD');
      expect(m, isNotNull);
      expect(m!.displayName, 'Mobilinkd TNC4');
      expect(m.family, BleKissFamily.aprsSpecs);
    });

    test('matches Mobilinkd TNC3 advertised names', () {
      final m = BleTncKnownDevice.matchByName('Mobilinkd TNC3 1234');
      expect(m?.displayName, 'Mobilinkd TNC3');
      expect(m?.family, BleKissFamily.aprsSpecs);
    });

    test('matches PicoAPRS', () {
      final m = BleTncKnownDevice.matchByName('PicoAPRS V4 1234');
      expect(m?.displayName, 'PicoAPRS v4');
      expect(m?.family, BleKissFamily.aprsSpecs);
    });

    test('matches B.B. Link variants', () {
      expect(
        BleTncKnownDevice.matchByName('BB-Link 0001')?.displayName,
        'B.B. Link',
      );
      expect(
        BleTncKnownDevice.matchByName('B.B. Link 1234')?.displayName,
        'B.B. Link',
      );
    });

    test('matches BTECH UV-Pro variants and resolves to Benshi family', () {
      expect(
        BleTncKnownDevice.matchByName('UV-PRO')?.family,
        BleKissFamily.benshi,
      );
      expect(
        BleTncKnownDevice.matchByName('BTECH UV-PRO')?.family,
        BleKissFamily.benshi,
      );
      expect(
        BleTncKnownDevice.matchByName('UV PRO 1234')?.displayName,
        'BTECH UV-Pro',
      );
    });

    test('matches Vero VR-N76 / VR-N7500', () {
      expect(
        BleTncKnownDevice.matchByName('VR-N76 1234')?.displayName,
        'Vero VR-N76',
      );
      expect(
        BleTncKnownDevice.matchByName('VR-N7500')?.displayName,
        'Vero VR-N7500',
      );
    });

    test('matches Radioddity GA-5WB', () {
      expect(
        BleTncKnownDevice.matchByName('GA-5WB 0001')?.family,
        BleKissFamily.benshi,
      );
      expect(
        BleTncKnownDevice.matchByName('Radioddity GA-5WB')?.displayName,
        'Radioddity GA-5WB',
      );
    });

    test('every registry entry has a non-empty display name and pattern', () {
      for (final entry in BleTncKnownDevice.all) {
        expect(entry.displayName, isNotEmpty);
        expect(entry.namePattern.pattern, isNotEmpty);
      }
    });

    test('every registry entry pattern is anchored to the start', () {
      // Stops "X mentions Mobilinkd somewhere" from matching the wrong row.
      for (final entry in BleTncKnownDevice.all) {
        expect(
          entry.namePattern.pattern.startsWith('^'),
          isTrue,
          reason: 'pattern for ${entry.displayName} must start with ^',
        );
      }
    });
  });
}
