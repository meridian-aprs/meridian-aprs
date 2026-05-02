import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_aprs/core/transport/ble_constants.dart';

void main() {
  group('bleKissFamilyForServiceUuids', () {
    test('matches the aprs-specs family service UUID', () {
      final family = bleKissFamilyForServiceUuids([kBleKissServiceUuid]);
      expect(family, BleKissFamily.aprsSpecs);
    });

    test('matches the Benshi family service UUID', () {
      final family = bleKissFamilyForServiceUuids([kBenshiKissServiceUuid]);
      expect(family, BleKissFamily.benshi);
    });

    test('matching is case-insensitive', () {
      final family = bleKissFamilyForServiceUuids([
        kBleKissServiceUuid.toUpperCase(),
      ]);
      expect(family, BleKissFamily.aprsSpecs);
    });

    test('returns null when no advertised UUID matches a known family', () {
      final family = bleKissFamilyForServiceUuids([
        '0000180f-0000-1000-8000-00805f9b34fb', // battery service
      ]);
      expect(family, isNull);
    });

    test('picks the first matching family when both are advertised', () {
      // Devices advertising both shouldn't exist in practice, but the resolver
      // must still pick deterministically — order is BleKissProfile.all.
      final family = bleKissFamilyForServiceUuids([
        kBenshiKissServiceUuid,
        kBleKissServiceUuid,
      ]);
      expect(family, BleKissFamily.aprsSpecs);
    });

    test('handles an empty list', () {
      expect(bleKissFamilyForServiceUuids(const []), isNull);
    });
  });

  group('BleKissProfile', () {
    test('aprsSpecs profile uses the standard UUIDs', () {
      const p = BleKissProfile.aprsSpecs;
      expect(p.serviceUuid, kBleKissServiceUuid);
      expect(p.writeCharUuid, kBleKissWriteCharUuid);
      expect(p.notifyCharUuid, kBleKissNotifyCharUuid);
      expect(p.family, BleKissFamily.aprsSpecs);
    });

    test('benshi profile uses the BTECH/Benshi UUIDs', () {
      const p = BleKissProfile.benshi;
      expect(p.serviceUuid, kBenshiKissServiceUuid);
      expect(p.writeCharUuid, kBenshiKissWriteCharUuid);
      expect(p.notifyCharUuid, kBenshiKissNotifyCharUuid);
      expect(p.family, BleKissFamily.benshi);
    });

    test('forFamily returns the right profile', () {
      expect(
        BleKissProfile.forFamily(BleKissFamily.aprsSpecs).serviceUuid,
        kBleKissServiceUuid,
      );
      expect(
        BleKissProfile.forFamily(BleKissFamily.benshi).serviceUuid,
        kBenshiKissServiceUuid,
      );
    });

    test('all profiles have distinct service UUIDs', () {
      final uuids = BleKissProfile.all.map((p) => p.serviceUuid).toSet();
      expect(uuids.length, BleKissProfile.all.length);
    });
  });
}
