import 'package:meridian_aprs/core/packet/device_resolver.dart';
import 'package:test/test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Hardcoded fallback — tested before any loadFromJson call so that static
  // state is the initial empty list (fallback table active).
  // ---------------------------------------------------------------------------

  group('DeviceResolver.resolve — tocall (hardcoded fallback)', () {
    test('APDR16 → APRSdroid', () {
      expect(DeviceResolver.resolve(tocall: 'APDR16'), equals('APRSdroid'));
    });

    test('APDW1.6 → Dire Wolf', () {
      expect(DeviceResolver.resolve(tocall: 'APDW1.6'), equals('Dire Wolf'));
    });

    test('APK004 → Kenwood TH-D7A', () {
      expect(
        DeviceResolver.resolve(tocall: 'APK004'),
        equals('Kenwood TH-D7A'),
      );
    });

    test('APWW10 → UI-View32', () {
      expect(DeviceResolver.resolve(tocall: 'APWW10'), equals('UI-View32'));
    });

    test('unknown tocall returns null', () {
      expect(DeviceResolver.resolve(tocall: 'APXXX'), isNull);
    });

    test('case-insensitive match on lowercase tocall', () {
      expect(DeviceResolver.resolve(tocall: 'apdr12'), equals('APRSdroid'));
    });

    test('tocall with SSID stripped before match', () {
      expect(DeviceResolver.resolve(tocall: 'APDW-7'), equals('Dire Wolf'));
    });

    test('APFII prefix → iPhone app (APRS.fi)', () {
      expect(
        DeviceResolver.resolve(tocall: 'APFII24'),
        equals('iPhone app (APRS.fi)'),
      );
    });

    test('APAGW prefix → AGWTracker', () {
      expect(DeviceResolver.resolve(tocall: 'APAGW0'), equals('AGWTracker'));
    });

    test('APRS (generic) matches', () {
      expect(DeviceResolver.resolve(tocall: 'APRS'), equals('APRS (generic)'));
    });
  });

  group('DeviceResolver.resolve — Mic-E suffix', () {
    test('suffix ] → Kenwood (TH-D7x/TM-D7x)', () {
      expect(
        DeviceResolver.resolve(micECommentSuffix: 'some comment]'),
        equals('Kenwood (TH-D7x/TM-D7x)'),
      );
    });

    test('suffix ]= → Kenwood TH-D72A', () {
      expect(
        DeviceResolver.resolve(micECommentSuffix: 'some comment]='),
        equals('Kenwood TH-D72A'),
      );
    });

    test('suffix ^ → Yaesu VX-8', () {
      expect(
        DeviceResolver.resolve(micECommentSuffix: 'comment^'),
        equals('Yaesu VX-8'),
      );
    });

    test('suffix ~ → Yaesu FT2D', () {
      expect(
        DeviceResolver.resolve(micECommentSuffix: 'comment~'),
        equals('Yaesu FT2D'),
      );
    });

    test('suffix _0 → Yaesu FT3D series', () {
      expect(
        DeviceResolver.resolve(micECommentSuffix: 'comment_0'),
        equals('Yaesu FT3D series'),
      );
    });

    test('suffix _9 → Yaesu FT3D series', () {
      expect(
        DeviceResolver.resolve(micECommentSuffix: 'comment_9'),
        equals('Yaesu FT3D series'),
      );
    });

    // `>` is a Kenwood TH-D7x *prefix* per aprs-deviceid, never a suffix.
    // Trailing `>IDENT` must not be interpreted as a device identifier —
    // this used to false-positive on any in-comment callsign mention.
    test('trailing `>FT3DR` does NOT resolve as a device', () {
      expect(
        DeviceResolver.resolve(micECommentSuffix: 'comment>FT3DR'),
        isNull,
      );
    });

    test('trailing `>AB` does NOT resolve as a device', () {
      expect(DeviceResolver.resolve(micECommentSuffix: 'hi>AB'), isNull);
    });

    test('no known pattern → null', () {
      expect(
        DeviceResolver.resolve(micECommentSuffix: 'just a plain comment'),
        isNull,
      );
    });

    test('empty suffix → null', () {
      expect(DeviceResolver.resolve(micECommentSuffix: ''), isNull);
    });

    test('generic > suffix that is too long (>10 chars) → null', () {
      expect(
        DeviceResolver.resolve(micECommentSuffix: 'comment>TOOLONGDEVICENAME'),
        isNull,
      );
    });

    test('generic > suffix that is 1 char → null (too short)', () {
      expect(DeviceResolver.resolve(micECommentSuffix: 'comment>X'), isNull);
    });
  });

  group('DeviceResolver.resolve — null inputs', () {
    test('both null → null', () {
      expect(DeviceResolver.resolve(), isNull);
    });

    test('empty tocall → null', () {
      expect(DeviceResolver.resolve(tocall: ''), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // JSON-backed lookup — uses synthetic JSON and resets state after each test.
  // ---------------------------------------------------------------------------

  group('DeviceResolver.loadFromJson — wildcard matching', () {
    const syntheticJson =
        '{"tocalls": {"APMDN?": {"model": "Meridian APRS", '
        '"vendor": "Eric Pasch, KM4TJO"}}}';

    setUp(() {
      DeviceResolver.loadFromJson(syntheticJson);
    });

    tearDown(() {
      DeviceResolver.resetForTesting();
    });

    test('APMDN0 resolves via ? wildcard', () {
      expect(DeviceResolver.resolve(tocall: 'APMDN0'), equals('Meridian APRS'));
    });

    test('APMDN1 resolves via ? wildcard', () {
      expect(DeviceResolver.resolve(tocall: 'APMDN1'), equals('Meridian APRS'));
    });

    test('APXXX returns null (unmatched)', () {
      expect(DeviceResolver.resolve(tocall: 'APXXX'), isNull);
    });

    test('null tocall returns null', () {
      expect(DeviceResolver.resolve(tocall: null), isNull);
    });
  });

  group('DeviceResolver.loadFromJson — specificity ordering', () {
    // Longer literal prefix wins over shorter prefix with wildcard.
    // APDR1 (5 literal chars) beats APDR? (4 literal chars) for input APDR10.
    const overlapJson =
        '{"tocalls": {'
        '"APDR1?": {"model": "APRSdroid Special"},'
        '"APDR??": {"model": "APRSdroid Generic"}'
        '}}';

    setUp(() {
      DeviceResolver.loadFromJson(overlapJson);
    });

    tearDown(() {
      DeviceResolver.resetForTesting();
    });

    test('APDR10 matches more-specific APDR1? over APDR??', () {
      expect(
        DeviceResolver.resolve(tocall: 'APDR10'),
        equals('APRSdroid Special'),
      );
    });

    test('APDR20 matches less-specific APDR?? when no APDR2? entry', () {
      expect(
        DeviceResolver.resolve(tocall: 'APDR20'),
        equals('APRSdroid Generic'),
      );
    });
  });

  group('DeviceResolver.loadFromJson — error resilience', () {
    test('invalid JSON does not throw', () {
      // Should not throw; prior state (fallback table) is preserved.
      expect(
        () => DeviceResolver.loadFromJson('not valid json'),
        returnsNormally,
      );
    });

    test('after bad JSON, hardcoded fallback still works', () {
      DeviceResolver.loadFromJson('not valid json');
      // Patterns list is unchanged; fallback table still active.
      expect(DeviceResolver.resolve(tocall: 'APDR16'), equals('APRSdroid'));
    });

    tearDown(() {
      DeviceResolver.resetForTesting();
    });
  });

  group('DeviceResolver.loadFromJson — model vs vendor fallback', () {
    const modelAndVendorJson =
        '{"tocalls": {"APTEST": {"model": "Test Model", "vendor": "Test Vendor"}}}';
    const vendorOnlyJson = '{"tocalls": {"APTEST": {"vendor": "Vendor Only"}}}';

    tearDown(() {
      DeviceResolver.resetForTesting();
    });

    test('model field is preferred over vendor', () {
      DeviceResolver.loadFromJson(modelAndVendorJson);
      expect(DeviceResolver.resolve(tocall: 'APTEST'), equals('Test Model'));
    });

    test('vendor used when model is absent', () {
      DeviceResolver.loadFromJson(vendorOnlyJson);
      expect(DeviceResolver.resolve(tocall: 'APTEST'), equals('Vendor Only'));
    });
  });
}
