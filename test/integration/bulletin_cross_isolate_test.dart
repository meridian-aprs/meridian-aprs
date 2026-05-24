/// Cross-isolate outgoing-bulletin propagation test for ADR-057/061 (ADR-062).
///
/// Proves the foreground/background state-drift fix end-to-end without an
/// Android foreground service: an outgoing bulletin is created on the "main"
/// connection, a worker isolate (standing in for the background isolate)
/// connects to the *same* `meridian.db` via the shared `DriftIsolate` port and
/// bumps the bulletin's transmission count, and the main-side
/// [BulletinService] reflects the bump after [BulletinService.refreshOutgoing]
/// — the same re-read the [BulletinScheduler] performs each tick.
library;

import 'dart:isolate';
import 'dart:ui';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_aprs/database/meridian_database.dart';
import 'package:meridian_aprs/services/bulletin_service.dart';
import 'package:meridian_aprs/services/bulletin_subscription_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _portName = 'meridian_drift_bulletin_test';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'background-isolate transmission bump is visible after refreshOutgoing',
    () async {
      SharedPreferences.setMockInitialValues({});
      IsolateNameServer.removePortNameMapping(_portName);

      final driftIsolate = await DriftIsolate.spawn(
        () => DatabaseConnection(NativeDatabase.memory()),
      );
      addTearDown(() async {
        await driftIsolate.shutdownAll();
        IsolateNameServer.removePortNameMapping(_portName);
      });
      IsolateNameServer.registerPortWithName(
        driftIsolate.connectPort,
        _portName,
      );

      final mainDb = MeridianDatabase.connect(await driftIsolate.connect());
      addTearDown(mainDb.close);

      final prefs = await SharedPreferences.getInstance();
      final subs = BulletinSubscriptionService(prefs: prefs);
      await subs.load();
      final service = BulletinService(
        subscriptions: subs,
        bulletinDao: mainDb.bulletinDao,
        prefs: prefs,
      );
      await service.load();

      // Main isolate creates an outgoing bulletin.
      final ob = await service.createOutgoing(
        addressee: 'BLN0',
        body: 'cross-isolate',
        intervalSeconds: 1800,
      );
      expect(service.outgoingById(ob.id)!.transmissionCount, 0);

      // Worker isolate (acting as the background service) bumps it.
      final workerDone = ReceivePort();
      await Isolate.spawn(_workerEntry, [workerDone.sendPort, ob.id]);
      final ack = await workerDone.first.timeout(const Duration(seconds: 5));
      expect(
        ack,
        isTrue,
        reason: 'worker isolate failed to record transmission',
      );

      // Before re-read, the main cache is still stale (polled, not pushed).
      expect(service.outgoingById(ob.id)!.transmissionCount, 0);

      // The scheduler's per-tick re-read picks up the background write.
      await service.refreshOutgoing();
      expect(service.outgoingById(ob.id)!.transmissionCount, 1);
      expect(service.outgoingById(ob.id)!.lastTransmittedAt, isNotNull);
    },
  );
}

/// Background-isolate entrypoint: connects to the shared drift port and records
/// one transmission against the given outgoing-bulletin id.
void _workerEntry(List<Object> args) async {
  final done = args[0] as SendPort;
  final id = args[1] as int;
  try {
    final port = IsolateNameServer.lookupPortByName(_portName);
    if (port == null) {
      done.send(false);
      return;
    }
    final isolate = DriftIsolate.fromConnectPort(port);
    final db = MeridianDatabase.connect(await isolate.connect());
    await db.bulletinDao.recordOutgoingTransmission(id, DateTime.now());
    await db.close();
    done.send(true);
  } catch (_) {
    done.send(false);
  }
}
