import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meridian_aprs/models/notification_preferences.dart';

void main() {
  group('NotificationPreferences', () {
    test('defaults — all channels enabled', () {
      final prefs = NotificationPreferences.defaults();
      for (final ch in NotificationChannels.all) {
        expect(prefs.isChannelEnabled(ch), isTrue, reason: 'channel $ch');
      }
    });

    test('defaults — sound on for messages and alerts, off elsewhere', () {
      final prefs = NotificationPreferences.defaults();
      expect(prefs.isSoundEnabled(NotificationChannels.messages), isTrue);
      expect(prefs.isSoundEnabled(NotificationChannels.alerts), isTrue);
      expect(prefs.isSoundEnabled(NotificationChannels.nearby), isFalse);
      expect(prefs.isSoundEnabled(NotificationChannels.system), isFalse);
    });

    test('defaults — vibration on for messages and alerts, off elsewhere', () {
      final prefs = NotificationPreferences.defaults();
      expect(prefs.isVibrationEnabled(NotificationChannels.messages), isTrue);
      expect(prefs.isVibrationEnabled(NotificationChannels.alerts), isTrue);
      expect(prefs.isVibrationEnabled(NotificationChannels.nearby), isFalse);
      expect(prefs.isVibrationEnabled(NotificationChannels.system), isFalse);
    });

    test('copyWithChannel toggles one channel without affecting others', () {
      final original = NotificationPreferences.defaults();
      final updated = original.copyWithChannel(
        NotificationChannels.messages,
        false,
      );
      expect(updated.isChannelEnabled(NotificationChannels.messages), isFalse);
      expect(updated.isChannelEnabled(NotificationChannels.alerts), isTrue);
    });

    test(
      'copyWithSound toggles one channel sound without affecting others',
      () {
        final original = NotificationPreferences.defaults();
        final updated = original.copyWithSound(
          NotificationChannels.messages,
          false,
        );
        expect(updated.isSoundEnabled(NotificationChannels.messages), isFalse);
        expect(updated.isSoundEnabled(NotificationChannels.alerts), isTrue);
      },
    );

    test('copyWithVibration toggles one channel vibration', () {
      final original = NotificationPreferences.defaults();
      final updated = original.copyWithVibration(
        NotificationChannels.nearby,
        true,
      );
      expect(updated.isVibrationEnabled(NotificationChannels.nearby), isTrue);
      expect(updated.isVibrationEnabled(NotificationChannels.messages), isTrue);
    });

    group('SharedPreferences round-trip', () {
      setUp(() {
        SharedPreferences.setMockInitialValues({});
      });

      test('save and reload reproduces same values', () async {
        final prefs = await SharedPreferences.getInstance();

        final original = NotificationPreferences.defaults()
            .copyWithChannel(NotificationChannels.alerts, false)
            .copyWithSound(NotificationChannels.messages, false)
            .copyWithVibration(NotificationChannels.nearby, true);

        await original.save(prefs);
        final loaded = await NotificationPreferences.load(prefs);

        expect(loaded.isChannelEnabled(NotificationChannels.alerts), isFalse);
        expect(loaded.isSoundEnabled(NotificationChannels.messages), isFalse);
        expect(loaded.isVibrationEnabled(NotificationChannels.nearby), isTrue);
        // Unchanged values preserved.
        expect(loaded.isChannelEnabled(NotificationChannels.messages), isTrue);
        expect(loaded.isSoundEnabled(NotificationChannels.alerts), isTrue);
      });

      test('load with no stored values returns defaults', () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final loaded = await NotificationPreferences.load(prefs);

        final defaults = NotificationPreferences.defaults();
        for (final ch in NotificationChannels.all) {
          expect(
            loaded.isChannelEnabled(ch),
            defaults.isChannelEnabled(ch),
            reason: 'channel $ch',
          );
          expect(
            loaded.isSoundEnabled(ch),
            defaults.isSoundEnabled(ch),
            reason: 'sound $ch',
          );
          expect(
            loaded.isVibrationEnabled(ch),
            defaults.isVibrationEnabled(ch),
            reason: 'vibration $ch',
          );
        }
      });
    });
  });
}
