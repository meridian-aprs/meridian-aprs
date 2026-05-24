/// Cross-isolate stream propagation test for ADR-062.
///
/// Spawns a dedicated drift isolate (owning an in-memory SQLite database),
/// registers its connect port via `IsolateNameServer`, then spawns a *worker*
/// isolate that looks up the port and inserts a packet row. The main isolate
/// subscribes to `PacketDao.watchRecent()` and asserts the worker's insert
/// arrives on the stream without any explicit re-read trigger — proving that
/// the foreground/background-isolate state-drift problem documented in
/// ADR-057 and ADR-061 is resolved by the shared `DriftIsolate` topology.
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:drift/drift.dart';
import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_aprs/core/packet/aprs_packet.dart' show PacketSource;
import 'package:meridian_aprs/database/meridian_database.dart';
import 'package:meridian_aprs/database/tables/packets.dart';

const _portName = 'meridian_drift_port_test';

void main() {
  test(
    'background-isolate write is visible on main-isolate watch() stream',
    () async {
      IsolateNameServer.removePortNameMapping(_portName);

      final driftIsolate = await DriftIsolate.spawn(
        () => DatabaseConnection(NativeDatabase.memory()),
      );

      addTearDown(() async {
        await driftIsolate.shutdownAll();
        IsolateNameServer.removePortNameMapping(_portName);
      });

      expect(
        IsolateNameServer.registerPortWithName(
          driftIsolate.connectPort,
          _portName,
        ),
        isTrue,
        reason: 'failed to register drift connect port',
      );

      final mainDb = MeridianDatabase.connect(await driftIsolate.connect());
      addTearDown(mainDb.close);

      // Force schema creation (no rows; drift opens lazily on first query).
      await mainDb.packetDao.watchRecent(limit: 1).first;

      final received = Completer<List<PacketRow>>();
      final sub = mainDb.packetDao.watchRecent(limit: 10).listen((rows) {
        if (rows.isNotEmpty && !received.isCompleted) {
          received.complete(rows);
        }
      });
      addTearDown(sub.cancel);

      final workerDone = ReceivePort();
      addTearDown(workerDone.close);
      await Isolate.spawn(_workerEntry, workerDone.sendPort);

      // Worker signals when its insert has been awaited.
      final ack = await workerDone.first.timeout(const Duration(seconds: 5));
      expect(ack, isTrue, reason: 'worker isolate failed to insert');

      final rows = await received.future.timeout(const Duration(seconds: 5));
      expect(rows, hasLength(1));
      expect(rows.single.rawLine, 'CROSS-ISOLATE>APMDN0:test');
      expect(rows.single.sourceCallsign, 'CROSS-ISOLATE');
      expect(rows.single.sourceChannel, PacketSource.aprsIs);
    },
  );
}

/// Background-isolate entrypoint: connects to the shared drift port and
/// performs a single insert.
void _workerEntry(SendPort done) async {
  try {
    final port = IsolateNameServer.lookupPortByName(_portName);
    if (port == null) {
      done.send(false);
      return;
    }
    final isolate = DriftIsolate.fromConnectPort(port);
    final db = MeridianDatabase.connect(await isolate.connect());
    await db.packetDao.insertPacket(
      PacketsCompanion.insert(
        rawLine: 'CROSS-ISOLATE>APMDN0:test',
        packetType: PacketTypeTag.unknown,
        sourceCallsign: 'CROSS-ISOLATE',
        receivedAt: DateTime.now().millisecondsSinceEpoch,
        sourceChannel: PacketSource.aprsIs,
      ),
    );
    await db.close();
    done.send(true);
  } catch (_) {
    done.send(false);
  }
}
