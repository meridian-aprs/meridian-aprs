import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meridian_aprs/core/packet/aprs_packet.dart';
import 'package:meridian_aprs/models/bulletin.dart';
import 'package:meridian_aprs/services/bulletin_service.dart';
import 'package:meridian_aprs/services/bulletin_subscription_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(BulletinService, BulletinSubscriptionService)> makeServices({
    List<String> subscribedGroups = const [],
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final subs = BulletinSubscriptionService(prefs: prefs);
    await subs.load();
    for (final g in subscribedGroups) {
      await subs.add(groupName: g, notify: false);
    }
    final bulletins = BulletinService(subscriptions: subs, prefs: prefs);
    await bulletins.load();
    return (bulletins, subs);
  }

  BulletinAddresseeInfo generalInfo(String line) => BulletinAddresseeInfo(
    addressee: 'BLN$line',
    lineNumber: line,
    category: BulletinCategory.general,
  );

  BulletinAddresseeInfo namedInfo(String line, String groupName) =>
      BulletinAddresseeInfo(
        addressee: 'BLN$line$groupName',
        lineNumber: line,
        category: BulletinCategory.groupNamed,
        groupName: groupName,
      );

  // ---------------------------------------------------------------------------

  group('general bulletin ingest', () {
    test('first receipt inserts with heardCount=1', () async {
      final (svc, _) = await makeServices();
      final outcome = svc.ingest(
        info: generalInfo('0'),
        sourceCallsign: 'K5WX-15',
        body: 'Severe weather alert',
        transport: PacketSource.aprsIs,
        receivedAt: DateTime(2026, 4, 23, 12, 0),
      );
      expect(outcome, BulletinIngestOutcome.inserted);
      expect(svc.bulletins, hasLength(1));
      final b = svc.bulletins.first;
      expect(b.heardCount, 1);
      expect(b.transports, {BulletinTransport.aprsIs});
      expect(b.isRead, isFalse);
    });

    test(
      'retransmission updates: bumps count, lastHeardAt, merges transports',
      () async {
        final (svc, _) = await makeServices();
        svc.ingest(
          info: generalInfo('0'),
          sourceCallsign: 'K5WX-15',
          body: 'Alert',
          transport: PacketSource.aprsIs,
          receivedAt: DateTime(2026, 4, 23, 12, 0),
        );
        final outcome = svc.ingest(
          info: generalInfo('0'),
          sourceCallsign: 'K5WX-15',
          body: 'Alert',
          transport: PacketSource.serialTnc,
          receivedAt: DateTime(2026, 4, 23, 12, 5),
        );
        expect(outcome, BulletinIngestOutcome.updated);
        expect(svc.bulletins, hasLength(1));
        final b = svc.bulletins.first;
        expect(b.heardCount, 2);
        expect(b.lastHeardAt, DateTime(2026, 4, 23, 12, 5));
        expect(b.transports, {BulletinTransport.aprsIs, BulletinTransport.rf});
      },
    );

    test('body change re-marks as unread', () async {
      final (svc, _) = await makeServices();
      svc.ingest(
        info: generalInfo('0'),
        sourceCallsign: 'K5WX-15',
        body: 'Old text',
        transport: PacketSource.aprsIs,
        receivedAt: DateTime(2026, 4, 23, 12, 0),
      );
      await svc.markRead(svc.bulletins.first.id);
      expect(svc.bulletins.first.isRead, isTrue);

      svc.ingest(
        info: generalInfo('0'),
        sourceCallsign: 'K5WX-15',
        body: 'New text',
        transport: PacketSource.aprsIs,
        receivedAt: DateTime(2026, 4, 23, 12, 10),
      );
      expect(svc.bulletins.first.body, 'New text');
      expect(svc.bulletins.first.isRead, isFalse);
    });

    test('body unchanged does not re-mark as unread', () async {
      final (svc, _) = await makeServices();
      svc.ingest(
        info: generalInfo('0'),
        sourceCallsign: 'K5WX-15',
        body: 'Same',
        transport: PacketSource.aprsIs,
        receivedAt: DateTime(2026, 4, 23, 12, 0),
      );
      await svc.markRead(svc.bulletins.first.id);
      svc.ingest(
        info: generalInfo('0'),
        sourceCallsign: 'K5WX-15',
        body: 'Same',
        transport: PacketSource.aprsIs,
        receivedAt: DateTime(2026, 4, 23, 12, 5),
      );
      expect(svc.bulletins.first.isRead, isTrue);
    });
  });

  group('named-group subscription filter', () {
    test('unsubscribed group is dropped', () async {
      final (svc, _) = await makeServices();
      final outcome = svc.ingest(
        info: namedInfo('1', 'WX'),
        sourceCallsign: 'K5WX-15',
        body: 'Radar update',
        transport: PacketSource.aprsIs,
        receivedAt: DateTime(2026, 4, 23, 12, 0),
      );
      expect(outcome, BulletinIngestOutcome.dropped);
      expect(svc.bulletins, isEmpty);
    });

    test('subscribed group is kept', () async {
      final (svc, _) = await makeServices(subscribedGroups: ['WX']);
      final outcome = svc.ingest(
        info: namedInfo('1', 'WX'),
        sourceCallsign: 'K5WX-15',
        body: 'Radar update',
        transport: PacketSource.aprsIs,
        receivedAt: DateTime(2026, 4, 23, 12, 0),
      );
      expect(outcome, BulletinIngestOutcome.inserted);
      expect(svc.bulletins, hasLength(1));
      expect(svc.bulletins.first.groupName, 'WX');
    });
  });

  group('persistence + retention', () {
    test('bulletins round-trip through SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final subs = BulletinSubscriptionService(prefs: prefs);
      await subs.load();
      final first = BulletinService(subscriptions: subs, prefs: prefs);
      await first.load();

      first.ingest(
        info: generalInfo('0'),
        sourceCallsign: 'K5WX-15',
        body: 'Alert',
        transport: PacketSource.aprsIs,
        receivedAt: DateTime(2026, 4, 23, 12, 0),
      );
      // Let persistence flush.
      await Future<void>.delayed(Duration.zero);

      final reloaded = BulletinService(subscriptions: subs, prefs: prefs);
      await reloaded.load();
      expect(reloaded.bulletins, hasLength(1));
      expect(reloaded.bulletins.first.body, 'Alert');
    });

    test('pruneOlderThan drops aged-out rows', () async {
      final (svc, _) = await makeServices();
      final old = DateTime.now().subtract(const Duration(hours: 72));
      final fresh = DateTime.now().subtract(const Duration(hours: 2));
      svc.ingest(
        info: generalInfo('0'),
        sourceCallsign: 'K5WX-1',
        body: 'Old',
        transport: PacketSource.aprsIs,
        receivedAt: old,
      );
      svc.ingest(
        info: generalInfo('1'),
        sourceCallsign: 'K5WX-2',
        body: 'Fresh',
        transport: PacketSource.aprsIs,
        receivedAt: fresh,
      );
      await svc.pruneOlderThan(const Duration(hours: 48));
      expect(svc.bulletins, hasLength(1));
      expect(svc.bulletins.first.body, 'Fresh');
    });
  });
}
