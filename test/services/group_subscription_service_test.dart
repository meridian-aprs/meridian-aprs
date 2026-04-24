import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meridian_aprs/models/group_subscription.dart';
import 'package:meridian_aprs/services/group_subscription_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('seeder (ADR-056 built-ins)', () {
    test('fresh install seeds ALL, CQ, QST, YAESU', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = GroupSubscriptionService(prefs: prefs);
      await service.load();

      final names = service.subscriptions.map((s) => s.name).toList();
      expect(names, containsAll(['ALL', 'CQ', 'QST', 'YAESU']));

      final byName = {for (final s in service.subscriptions) s.name: s};
      expect(byName['CQ']!.enabled, isTrue);
      expect(byName['QST']!.enabled, isTrue);
      expect(byName['ALL']!.enabled, isFalse);
      expect(byName['YAESU']!.enabled, isFalse);

      // All built-ins default to reply-to-sender + notify off.
      for (final name in ['ALL', 'CQ', 'QST', 'YAESU']) {
        expect(byName[name]!.replyMode, ReplyMode.sender);
        expect(byName[name]!.notify, isFalse);
        expect(byName[name]!.isBuiltin, isTrue);
      }
    });

    test(
      'seeder is idempotent — second load does not duplicate or reset',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        final first = GroupSubscriptionService(prefs: prefs);
        await first.load();
        // User toggles ALL on; this must survive re-load.
        final allId = first.subscriptions.firstWhere((s) => s.name == 'ALL').id;
        await first.update(allId, enabled: true);

        final second = GroupSubscriptionService(prefs: prefs);
        await second.load();
        final secondAll = second.subscriptions.firstWhere(
          (s) => s.name == 'ALL',
        );
        expect(secondAll.enabled, isTrue);
        // Still only 4 built-ins (no duplicate seed).
        final builtins = second.subscriptions
            .where((s) => s.isBuiltin)
            .toList();
        expect(builtins.length, 4);
      },
    );
  });

  group('custom groups', () {
    test('add + delete round-trips through SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = GroupSubscriptionService(prefs: prefs);
      await service.load();

      final srarc = await service.add(name: 'SRARC');
      expect(srarc.name, 'SRARC');
      expect(srarc.isBuiltin, isFalse);
      // Custom default is reply-to-group.
      expect(srarc.replyMode, ReplyMode.group);

      // Persist across service instance.
      final reloaded = GroupSubscriptionService(prefs: prefs);
      await reloaded.load();
      expect(reloaded.subscriptions.any((s) => s.name == 'SRARC'), isTrue);

      // Delete.
      await reloaded.delete(srarc.id);
      final after = GroupSubscriptionService(prefs: prefs);
      await after.load();
      expect(after.subscriptions.any((s) => s.name == 'SRARC'), isFalse);
    });

    test('rejects invalid name', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = GroupSubscriptionService(prefs: prefs);
      await service.load();
      expect(() => service.add(name: 'too-long-name'), throwsArgumentError);
      expect(() => service.add(name: 'BAD!'), throwsArgumentError);
      expect(() => service.add(name: ''), throwsArgumentError);
    });

    test('rejects duplicate name (case-insensitive)', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = GroupSubscriptionService(prefs: prefs);
      await service.load();
      await service.add(name: 'CLUB');
      expect(() => service.add(name: 'club'), throwsArgumentError);
    });

    test('cannot delete or rename built-ins', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = GroupSubscriptionService(prefs: prefs);
      await service.load();
      final cq = service.subscriptions.firstWhere((s) => s.name == 'CQ');
      expect(() => service.delete(cq.id), throwsStateError);
      expect(() => service.update(cq.id, name: 'CQCQCQ'), throwsStateError);
    });
  });

  group('reorder', () {
    test('reorder preserves content and is observable', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = GroupSubscriptionService(prefs: prefs);
      await service.load();

      final ids = service.subscriptions.map((s) => s.id).toList();
      final reversed = ids.reversed.toList();
      await service.reorder(reversed);

      expect(service.subscriptions.map((s) => s.id).toList(), reversed);
    });
  });
}
