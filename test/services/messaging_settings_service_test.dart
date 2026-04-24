import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meridian_aprs/services/messaging_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('defaults', () {
    test('empty group message path means "same as beacon path"', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final svc = MessagingSettingsService(prefs: prefs);
      await svc.load();
      expect(svc.groupMessagePath, isEmpty);
      expect(
        svc.effectiveGroupMessagePath,
        MessagingSettingsService.resolvedDefaultGroupMessagePath,
      );
    });

    test('default bulletin path is WIDE2-2', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final svc = MessagingSettingsService(prefs: prefs);
      await svc.load();
      expect(svc.bulletinPath, 'WIDE2-2');
    });

    test('default muted sources is empty', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final svc = MessagingSettingsService(prefs: prefs);
      await svc.load();
      expect(svc.mutedBulletinSources, isEmpty);
    });
  });

  group('persistence', () {
    test('group message path round-trips', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final first = MessagingSettingsService(prefs: prefs);
      await first.load();
      await first.setGroupMessagePath('WIDE1-1');

      final second = MessagingSettingsService(prefs: prefs);
      await second.load();
      expect(second.groupMessagePath, 'WIDE1-1');
      expect(second.effectiveGroupMessagePath, 'WIDE1-1');
    });

    test('setting group message path to empty clears the pref', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final svc = MessagingSettingsService(prefs: prefs);
      await svc.load();
      await svc.setGroupMessagePath('WIDE1-1');
      await svc.setGroupMessagePath('');
      expect(svc.groupMessagePath, isEmpty);
      expect(
        svc.effectiveGroupMessagePath,
        MessagingSettingsService.resolvedDefaultGroupMessagePath,
      );
    });

    test('bulletin path rejects empty', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final svc = MessagingSettingsService(prefs: prefs);
      await svc.load();
      expect(() => svc.setBulletinPath(''), throwsArgumentError);
      expect(() => svc.setBulletinPath('   '), throwsArgumentError);
      expect(svc.bulletinPath, 'WIDE2-2');
    });

    test('muted sources add/remove + uppercase normalization', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final svc = MessagingSettingsService(prefs: prefs);
      await svc.load();
      await svc.addMutedBulletinSource('k5wx-15');
      expect(svc.mutedBulletinSources, contains('K5WX-15'));

      // Add again — should be idempotent.
      await svc.addMutedBulletinSource('K5WX-15');
      expect(svc.mutedBulletinSources.length, 1);

      await svc.removeMutedBulletinSource('K5WX-15');
      expect(svc.mutedBulletinSources, isEmpty);
    });

    test('muted sources persist across service instances', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final first = MessagingSettingsService(prefs: prefs);
      await first.load();
      await first.addMutedBulletinSource('N0CALL-7');

      final second = MessagingSettingsService(prefs: prefs);
      await second.load();
      expect(second.mutedBulletinSources, contains('N0CALL-7'));
    });
  });
}
