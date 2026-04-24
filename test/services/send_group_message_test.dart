/// Tests for `MessageService.sendGroupMessage` (v0.17 PR 4, ADR-056).
///
/// Verifies wire-format, digipeater path override, no wire ID, and own-SSID
/// echo into the group conversation.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meridian_aprs/core/connection/connection_registry.dart';
import 'package:meridian_aprs/models/message_category.dart';
import 'package:meridian_aprs/services/bulletin_service.dart';
import 'package:meridian_aprs/services/bulletin_subscription_service.dart';
import 'package:meridian_aprs/services/group_subscription_service.dart';
import 'package:meridian_aprs/services/message_service.dart';
import 'package:meridian_aprs/services/station_service.dart';
import 'package:meridian_aprs/services/station_settings_service.dart';
import 'package:meridian_aprs/services/tx_service.dart';

import '../helpers/fake_secure_credential_store.dart';

class _SendCapture {
  _SendCapture(this.line, this.digipeaterPath, this.forceVia);
  final String line;
  final List<String>? digipeaterPath;
  final ConnectionType? forceVia;
}

class _CapturingTxService extends TxService {
  _CapturingTxService(super.registry, super.settings, this.sends);
  final List<_SendCapture> sends;

  @override
  Future<void> sendLine(
    String aprsLine, {
    ConnectionType? forceVia,
    List<String>? digipeaterPath,
  }) async {
    sends.add(_SendCapture(aprsLine, digipeaterPath, forceVia));
  }
}

Future<MessageService> _buildService({
  required List<_SendCapture> sends,
}) async {
  SharedPreferences.setMockInitialValues({
    'user_callsign': 'W1ABC',
    'user_ssid': 7,
    'user_is_licensed': true,
  });
  final prefs = await SharedPreferences.getInstance();
  final settings = StationSettingsService(
    prefs,
    store: FakeSecureCredentialStore(),
  );
  final registry = ConnectionRegistry();
  final tx = _CapturingTxService(registry, settings, sends);

  final groups = GroupSubscriptionService(prefs: prefs);
  await groups.load();
  final bulletinSubs = BulletinSubscriptionService(prefs: prefs);
  await bulletinSubs.load();
  final bulletins = BulletinService(subscriptions: bulletinSubs, prefs: prefs);
  await bulletins.load();

  return MessageService(
    settings,
    tx,
    StationService(),
    groupSubscriptions: groups,
    bulletins: bulletins,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('encodes group message with correct pad and no wire ID', () async {
    final sends = <_SendCapture>[];
    final service = await _buildService(sends: sends);
    await service.sendGroupMessage('CQ', 'CQ CQ — anyone on freq?');

    expect(sends, hasLength(1));
    final line = sends.first.line;
    expect(line, contains('::CQ       :CQ CQ — anyone on freq?'));
    // No wire ID — groups are never ACKed.
    expect(line, isNot(contains('{')));
  });

  test('threads digipeater path override through to sendLine', () async {
    final sends = <_SendCapture>[];
    final service = await _buildService(sends: sends);
    await service.sendGroupMessage(
      'CLUB',
      'Net starting',
      rfPath: const ['WIDE1-1', 'WIDE2-1'],
    );
    expect(sends.first.digipeaterPath, ['WIDE1-1', 'WIDE2-1']);
  });

  test('null rfPath passes null through (encoder default applies)', () async {
    final sends = <_SendCapture>[];
    final service = await _buildService(sends: sends);
    await service.sendGroupMessage('CQ', 'x');
    expect(sends.first.digipeaterPath, isNull);
  });

  test('appends own-SSID echo to the group conversation', () async {
    final sends = <_SendCapture>[];
    final service = await _buildService(sends: sends);
    await service.sendGroupMessage('CQ', 'hello group');

    final conv = service.conversationForGroup('CQ');
    expect(conv, isNotNull);
    expect(conv!.messages, hasLength(1));
    final entry = conv.messages.first;
    expect(entry.isOutgoing, isTrue);
    expect(entry.text, 'hello group');
    expect(entry.category, MessageCategory.group);
    expect(entry.groupName, 'CQ');
    // No wire ID — mirrors the wire format.
    expect(entry.wireId, isNull);
    // Marked as delivered (no ACK to wait for).
    expect(entry.status, MessageStatus.acked);
  });

  test('empty group name is a no-op', () async {
    final sends = <_SendCapture>[];
    final service = await _buildService(sends: sends);
    await service.sendGroupMessage('', 'x');
    expect(sends, isEmpty);
  });

  test('uppercases the group name before encoding', () async {
    final sends = <_SendCapture>[];
    final service = await _buildService(sends: sends);
    await service.sendGroupMessage('cq', 'x');
    expect(sends.first.line, contains('::CQ       :x'));
  });
}
