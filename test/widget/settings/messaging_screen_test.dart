/// Widget tests for `MessagingSettingsContent`. Covers the v0.17 PR 2
/// additions — Groups subsection, Bulletins subsection, Advanced-mode path
/// fields — plus the pre-existing v0.14 Cross-SSID section to confirm no
/// regression.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meridian_aprs/core/connection/connection_registry.dart';
import 'package:meridian_aprs/models/notification_preferences.dart';
import 'package:meridian_aprs/screens/settings/advanced_mode_controller.dart';
import 'package:meridian_aprs/screens/settings/category/messaging_screen.dart';
import 'package:meridian_aprs/services/bulletin_service.dart';
import 'package:meridian_aprs/services/bulletin_subscription_service.dart';
import 'package:meridian_aprs/services/group_subscription_service.dart';
import 'package:meridian_aprs/services/message_service.dart';
import 'package:meridian_aprs/services/messaging_settings_service.dart';
import 'package:meridian_aprs/services/notification_service.dart';
import 'package:meridian_aprs/services/station_service.dart';
import 'package:meridian_aprs/services/station_settings_service.dart';
import 'package:meridian_aprs/services/tx_service.dart';
import 'package:meridian_aprs/ui/widgets/in_app_banner_overlay.dart';

import '../../helpers/fake_secure_credential_store.dart';

// ---------------------------------------------------------------------------
// Test harness
// ---------------------------------------------------------------------------

class _Harness {
  _Harness._({
    required this.groups,
    required this.bulletinSubs,
    required this.bulletins,
    required this.messagingSettings,
    required this.advanced,
    required this.widget,
  });

  final GroupSubscriptionService groups;
  final BulletinSubscriptionService bulletinSubs;
  final BulletinService bulletins;
  final MessagingSettingsService messagingSettings;
  final AdvancedModeController advanced;
  final Widget widget;

  static Future<_Harness> create() async {
    SharedPreferences.setMockInitialValues({
      'user_callsign': 'W1ABC',
      'user_ssid': 7,
    });
    final prefs = await SharedPreferences.getInstance();
    final settings = StationSettingsService(
      prefs,
      store: FakeSecureCredentialStore(),
    );
    final registry = ConnectionRegistry();
    final stationService = StationService();
    final tx = TxService(registry, settings);

    final groups = GroupSubscriptionService(prefs: prefs);
    await groups.load();
    final bulletinSubs = BulletinSubscriptionService(prefs: prefs);
    await bulletinSubs.load();
    final bulletins = BulletinService(
      subscriptions: bulletinSubs,
      prefs: prefs,
    );
    await bulletins.load();
    final messagingSettings = MessagingSettingsService(prefs: prefs);
    await messagingSettings.load();
    final advanced = await AdvancedModeController.create();

    final messageService = MessageService(
      settings,
      tx,
      stationService,
      groupSubscriptions: groups,
      bulletins: bulletins,
    );
    final notifService = NotificationService(
      messageService: messageService,
      prefs: prefs,
      navigatorKey: GlobalKey<NavigatorState>(),
      bannerController: InAppBannerController(),
    );
    // Seed notif prefs without touching platform channels.
    await NotificationPreferences.defaults(optedIn: true).save(prefs);

    final widget = MaterialApp(
      home: Scaffold(
        body: MultiProvider(
          providers: [
            ChangeNotifierProvider<StationSettingsService>.value(
              value: settings,
            ),
            ChangeNotifierProvider<MessageService>.value(value: messageService),
            ChangeNotifierProvider<NotificationService>.value(
              value: notifService,
            ),
            ChangeNotifierProvider<GroupSubscriptionService>.value(
              value: groups,
            ),
            ChangeNotifierProvider<BulletinSubscriptionService>.value(
              value: bulletinSubs,
            ),
            ChangeNotifierProvider<BulletinService>.value(value: bulletins),
            ChangeNotifierProvider<MessagingSettingsService>.value(
              value: messagingSettings,
            ),
            ChangeNotifierProvider<AdvancedModeController>.value(
              value: advanced,
            ),
          ],
          child: const MessagingSettingsContent(),
        ),
      ),
    );

    return _Harness._(
      groups: groups,
      bulletinSubs: bulletinSubs,
      bulletins: bulletins,
      messagingSettings: messagingSettings,
      advanced: advanced,
      widget: widget,
    );
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // SectionHeader uppercases its title on render.

  testWidgets('renders all three section headers', (tester) async {
    final h = await _Harness.create();
    await tester.pumpWidget(h.widget);
    await tester.pumpAndSettle();
    // Top of list — Cross-SSID Messages — is always visible.
    expect(find.text('CROSS-SSID MESSAGES'), findsOneWidget);
    // Groups + Bulletins may be below the fold in the test viewport;
    // scroll through the list to confirm they render.
    await tester.scrollUntilVisible(
      find.text('GROUPS'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('GROUPS'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('BULLETINS'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('BULLETINS'), findsOneWidget);
  });

  testWidgets('built-in groups appear in the list', (tester) async {
    final h = await _Harness.create();
    await tester.pumpWidget(h.widget);
    await tester.pumpAndSettle();
    // Scroll until CQ is visible. Default seeded set includes CQ + QST.
    await tester.scrollUntilVisible(
      find.text('CQ'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('CQ'), findsOneWidget);
    expect(find.text('QST'), findsOneWidget);
  });

  testWidgets('Advanced-mode path fields hidden when advanced mode is off', (
    tester,
  ) async {
    final h = await _Harness.create();
    await tester.pumpWidget(h.widget);
    await tester.pumpAndSettle();
    // Scroll to the bottom in case the section existed — then assert none.
    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, -3000),
    );
    await tester.pumpAndSettle();
    expect(find.text('Group message path'), findsNothing);
    expect(find.text('Bulletin path'), findsNothing);
    expect(find.text('Muted bulletin sources'), findsNothing);
  });

  testWidgets('Advanced-mode path fields appear when toggled on', (
    tester,
  ) async {
    final h = await _Harness.create();
    await h.advanced.setEnabled(true);
    await tester.pumpWidget(h.widget);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Bulletin path'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Bulletin path'), findsOneWidget);
    expect(find.text('Muted bulletin sources'), findsOneWidget);
    // Group message path is rendered above in the Groups section.
    await tester.scrollUntilVisible(
      find.text('Group message path'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Group message path'), findsOneWidget);
  });

  testWidgets('Show bulletins toggle wires through service', (tester) async {
    final h = await _Harness.create();
    await tester.pumpWidget(h.widget);
    await tester.pumpAndSettle();

    expect(h.bulletins.showBulletins, isTrue);
    await tester.scrollUntilVisible(
      find.text('Show bulletins'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Show bulletins'));
    await tester.pumpAndSettle();
    expect(h.bulletins.showBulletins, isFalse);
  });

  testWidgets('named bulletin subscription empty state copy renders', (
    tester,
  ) async {
    final h = await _Harness.create();
    await tester.pumpWidget(h.widget);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('No named-group subscriptions'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('No named-group subscriptions'), findsOneWidget);
  });
}
