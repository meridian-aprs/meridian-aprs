import 'package:test/test.dart';
import 'package:meridian_aprs/core/transport/tnc_config.dart';
import 'package:meridian_aprs/core/transport/tnc_preset.dart';

void main() {
  group('TncConfig', () {
    // -------------------------------------------------------------------------
    // fromPreset
    // -------------------------------------------------------------------------

    test('fromPreset copies all serial parameters', () {
      final config = TncConfig.fromPreset(
        TncPreset.mobilinkdTnc4,
        port: '/dev/ttyACM0',
      );

      expect(config.port, equals('/dev/ttyACM0'));
      expect(config.baudRate, equals(115200));
      expect(config.dataBits, equals(8));
      expect(config.stopBits, equals(1));
      expect(config.parity, equals('none'));
      expect(config.hardwareFlowControl, isFalse);
      expect(config.presetId, equals('mobilinkd_tnc4'));
    });

    // -------------------------------------------------------------------------
    // toPrefsMap / fromPrefsMap round-trip
    // -------------------------------------------------------------------------

    test('toPrefsMap/fromPrefsMap round-trip preserves all fields', () {
      const original = TncConfig(
        port: '/dev/ttyUSB1',
        baudRate: 57600,
        dataBits: 7,
        stopBits: 2,
        parity: 'even',
        hardwareFlowControl: true,
        kissTxDelayMs: 100,
        kissPersistence: 128,
        kissSlotTimeMs: 20,
        presetId: 'mobilinkd_tnc4',
      );

      final map = original.toPrefsMap();
      final restored = TncConfig.fromPrefsMap(map);

      expect(restored, isNotNull);
      expect(restored!.port, equals(original.port));
      expect(restored.baudRate, equals(original.baudRate));
      expect(restored.dataBits, equals(original.dataBits));
      expect(restored.stopBits, equals(original.stopBits));
      expect(restored.parity, equals(original.parity));
      expect(
        restored.hardwareFlowControl,
        equals(original.hardwareFlowControl),
      );
      expect(restored.kissTxDelayMs, equals(original.kissTxDelayMs));
      expect(restored.kissPersistence, equals(original.kissPersistence));
      expect(restored.kissSlotTimeMs, equals(original.kissSlotTimeMs));
      expect(restored.presetId, equals(original.presetId));
    });

    // -------------------------------------------------------------------------
    // fromPrefsMap — null / missing cases
    // -------------------------------------------------------------------------

    test('fromPrefsMap returns null when tnc_port is absent', () {
      final result = TncConfig.fromPrefsMap({});
      expect(result, isNull);
    });

    test('fromPrefsMap returns null when tnc_port is empty string', () {
      final result = TncConfig.fromPrefsMap({'tnc_port': ''});
      expect(result, isNull);
    });

    // -------------------------------------------------------------------------
    // fromPrefsMap — defaults
    // -------------------------------------------------------------------------

    test('defaults apply when optional prefs keys absent', () {
      final result = TncConfig.fromPrefsMap({'tnc_port': '/dev/ttyUSB0'});

      expect(result, isNotNull);
      expect(result!.baudRate, equals(9600));
      expect(result.kissTxDelayMs, equals(50));
      expect(result.kissPersistence, equals(63));
      expect(result.kissSlotTimeMs, equals(10));
    });
  });
}
