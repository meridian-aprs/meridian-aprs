/// Widget tests for the v0.17 Messages screen rework (PR 3).
///
/// Covers:
///   - Segmented control renders three tabs and the Direct body is visible
///     by default (the v0.14 compose FAB is unchanged when Direct is active).
///   - Tapping the Groups / Bulletins segments swaps the body.
///   - Bulletins tab respects the `showBulletins` master toggle.
///   - Location-unknown banner shows only when APRS-IS is connected AND no
///     station location has been set.
///   - Bulletin detail has no inline reply affordance.
///   - Group channel shows adaptive compose based on `replyMode`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meridian_aprs/core/connection/connection_registry.dart';
import 'package:meridian_aprs/core/packet/aprs_packet.dart';
import 'package:meridian_aprs/models/bulletin.dart';
import 'package:meridian_aprs/models/notification_preferences.dart';
import 'package:meridian_aprs/screens/bulletin_detail_screen.dart';
import 'package:meridian_aprs/screens/group_channel_screen.dart';
import 'package:meridian_aprs/screens/messages_screen.dart';
import 'package:meridian_aprs/services/bulletin_service.dart';
import 'package:meridian_aprs/services/bulletin_subscription_service.dart';
import 'package:meridian_aprs/services/group_subscription_service.dart';
import 'package:meridian_aprs/services/message_service.dart';
import 'package:meridian_aprs/services/messaging_settings_service.dart';
import 'package:meridian_aprs/services/station_service.dart';
import 'package:meridian_aprs/services/station_settings_service.dart';
import 'package:meridian_aprs/services/tx_service.dart';

import '../../helpers/fake_meridian_connection.dart';
import '../../helpers/fake_secure_credential_store.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

class _Harness {
  _Harness._({
    required this.messages,
    required this.bulletins,
    required this.bulletinSubs,
    required this.groupSubs,
    required this.settings,
    required this.registry,
    required this.aprsIsConn,
  });

  final MessageService messages;
  final BulletinService bulletins;
  final BulletinSubscriptionService bulletinSubs;
  final GroupSubscriptionService groupSubs;
  final StationSettingsService settings;
  final ConnectionRegistry registry;
  final FakeMeridianConnection aprsIsConn;

  static Future<_Harness> create({
    bool licensed = true,
    bool manualLocation = false,
    bool aprsIsConnected = false,
    bool showBulletinsEnabled = true,
  }) async {
    SharedPreferences.setMockInitialValues({
      'user_callsign': 'W1ABC',
      'user_ssid': 7,
      'user_is_licensed': licensed,
    });
    final prefs = await SharedPreferences.getInstance();
    final settings = StationSettingsService(
      prefs,
      store: FakeSecureCredentialStore(),
    );
    if (manualLocation) {
      await settings.setManualPosition(42.0, -71.0);
    }

    final aprsIsConn = FakeMeridianConnection(
      id: 'aprs_is',
      displayName: 'APRS-IS',
      type: ConnectionType.aprsIs,
    );
    final registry = ConnectionRegistry();
    registry.register(aprsIsConn);
    if (aprsIsConnected) {
      aprsIsConn.setStatus(ConnectionStatus.connected);
    }

    final stationService = StationService();
    final tx = TxService(registry, settings);

    final groupSubs = GroupSubscriptionService(prefs: prefs);
    await groupSubs.load();
    final bulletinSubs = BulletinSubscriptionService(prefs: prefs);
    await bulletinSubs.load();
    final bulletins = BulletinService(
      subscriptions: bulletinSubs,
      prefs: prefs,
    );
    await bulletins.load();
    if (!showBulletinsEnabled) {
      await bulletins.setShowBulletins(false);
    }

    final messagingSettings = MessagingSettingsService(prefs: prefs);
    await messagingSettings.load();

    final messages = MessageService(
      settings,
      tx,
      stationService,
      groupSubscriptions: groupSubs,
      bulletins: bulletins,
    );

    // Seed notification prefs so downstream widgets that read them don't
    // hit an uninitialized pref. We don't need a NotificationService in the
    // widget tree — the screens this test exercises don't read it.
    await NotificationPreferences.defaults(optedIn: true).save(prefs);

    return _Harness._(
      messages: messages,
      bulletins: bulletins,
      bulletinSubs: bulletinSubs,
      groupSubs: groupSubs,
      settings: settings,
      registry: registry,
      aprsIsConn: aprsIsConn,
    );
  }

  Widget wrap(Widget child) => MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<StationSettingsService>.value(value: settings),
        ChangeNotifierProvider<ConnectionRegistry>.value(value: registry),
        ChangeNotifierProvider<MessageService>.value(value: messages),
        ChangeNotifierProvider<BulletinService>.value(value: bulletins),
        ChangeNotifierProvider<BulletinSubscriptionService>.value(
          value: bulletinSubs,
        ),
        ChangeNotifierProvider<GroupSubscriptionService>.value(
          value: groupSubs,
        ),
      ],
      child: child,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MessagesScreen — segmented control', () {
    testWidgets('renders Direct / Groups / Bulletins segments', (tester) async {
      final h = await _Harness.create();
      await tester.pumpWidget(h.wrap(const MessagesScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Direct'), findsOneWidget);
      expect(find.text('Groups'), findsOneWidget);
      expect(find.text('Bulletins'), findsOneWidget);
    });

    testWidgets('tapping Groups swaps to the group tab empty state', (
      tester,
    ) async {
      final h = await _Harness.create();
      await tester.pumpWidget(h.wrap(const MessagesScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Groups'));
      await tester.pumpAndSettle();

      // Built-ins (CQ/QST/ALL) seed on first run — we expect at least CQ.
      expect(find.text('CQ'), findsWidgets);
    });

    testWidgets('tapping Bulletins swaps to bulletins-tab empty state', (
      tester,
    ) async {
      final h = await _Harness.create();
      await tester.pumpWidget(h.wrap(const MessagesScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bulletins'));
      await tester.pumpAndSettle();
      expect(find.text('No bulletins yet'), findsOneWidget);
    });
  });

  group('BulletinsTab — showBulletins gate', () {
    testWidgets('showBulletins=false hides the feed with disabled state', (
      tester,
    ) async {
      final h = await _Harness.create(showBulletinsEnabled: false);
      await tester.pumpWidget(h.wrap(const MessagesScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bulletins'));
      await tester.pumpAndSettle();
      expect(find.text('Bulletins are hidden'), findsOneWidget);
    });
  });

  group('BulletinsTab — location-unknown banner', () {
    testWidgets('banner shows when APRS-IS connected + no station location', (
      tester,
    ) async {
      final h = await _Harness.create(
        aprsIsConnected: true,
        manualLocation: false,
      );
      await tester.pumpWidget(h.wrap(const MessagesScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bulletins'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('station location is not set'),
        findsOneWidget,
      );
      expect(find.text('Set location'), findsOneWidget);
    });

    testWidgets('banner hidden when APRS-IS disconnected', (tester) async {
      final h = await _Harness.create(
        aprsIsConnected: false,
        manualLocation: false,
      );
      await tester.pumpWidget(h.wrap(const MessagesScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bulletins'));
      await tester.pumpAndSettle();

      expect(find.textContaining('station location is not set'), findsNothing);
    });

    testWidgets('banner hidden when station location is set', (tester) async {
      final h = await _Harness.create(
        aprsIsConnected: true,
        manualLocation: true,
      );
      await tester.pumpWidget(h.wrap(const MessagesScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bulletins'));
      await tester.pumpAndSettle();

      expect(find.textContaining('station location is not set'), findsNothing);
    });
  });

  group('BulletinDetailScreen', () {
    testWidgets('renders body, source, totals, no inline reply input', (
      tester,
    ) async {
      final h = await _Harness.create();
      // Seed a bulletin.
      h.bulletins.ingest(
        info: const BulletinAddresseeInfo(
          addressee: 'BLN0',
          lineNumber: '0',
          category: BulletinCategory.general,
        ),
        sourceCallsign: 'K5WX-15',
        body: 'Severe weather alert',
        transport: PacketSource.aprsIs,
        receivedAt: DateTime(2026, 4, 23, 12, 0),
      );
      final bulletinId = h.bulletins.bulletins.first.id;

      await tester.pumpWidget(
        h.wrap(BulletinDetailScreen(bulletinId: bulletinId)),
      );
      await tester.pumpAndSettle();

      expect(find.text('BLN0'), findsWidgets);
      expect(find.text('Severe weather alert'), findsOneWidget);
      expect(find.text('From K5WX-15'), findsOneWidget);
      expect(find.text('Total receipts'), findsOneWidget);

      // Critical: bulletin detail is read-only — no TextField should exist.
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('GroupChannelScreen — adaptive compose', () {
    testWidgets('sender-mode compose shows reply hint when no last sender', (
      tester,
    ) async {
      final h = await _Harness.create();
      // CQ is seeded as reply_mode = sender.
      await tester.pumpWidget(
        h.wrap(const GroupChannelScreen(groupName: 'CQ')),
      );
      await tester.pumpAndSettle();

      // With no incoming messages yet, compose falls back to "Message to CQ".
      expect(find.text('Message to CQ'), findsWidgets);
    });

    testWidgets('group-mode custom group shows "Message to NAME"', (
      tester,
    ) async {
      final h = await _Harness.create();
      await h.groupSubs.add(name: 'SRARC'); // defaults to replyMode.group
      await tester.pumpWidget(
        h.wrap(const GroupChannelScreen(groupName: 'SRARC')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Message to SRARC'), findsWidgets);
    });

    testWidgets('missing subscription renders the fallback bar', (
      tester,
    ) async {
      final h = await _Harness.create();
      await tester.pumpWidget(
        h.wrap(const GroupChannelScreen(groupName: 'DOESNOTEXIST')),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('This group is no longer in your subscriptions'),
        findsOneWidget,
      );
    });

    testWidgets('unlicensed user sees unlicensed bar instead of compose', (
      tester,
    ) async {
      final h = await _Harness.create(licensed: false);
      await tester.pumpWidget(
        h.wrap(const GroupChannelScreen(groupName: 'CQ')),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('amateur radio license is required'),
        findsOneWidget,
      );
    });
  });
}
