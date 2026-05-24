import 'dart:io';
import 'dart:ui';

import 'package:drift/drift.dart';
import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:path_provider/path_provider.dart';

import 'meridian_database.dart';

/// Name under which the shared drift connect port is registered with
/// `IsolateNameServer`. The Android foreground-service background isolate
/// looks it up via [lookupBackgroundDatabasePort] to obtain a client
/// connection on the same `meridian.db` opened by the main isolate.
const String meridianDriftPortName = 'meridian_drift_port';

/// Spawns a dedicated drift isolate that owns `meridian.db`, registers its
/// connect port for cross-isolate use, and returns a main-isolate client
/// connected through that port.
///
/// On web the cross-isolate machinery is a no-op (no `dart:isolate`,
/// `flutter_foreground_task` is unavailable) — the database is opened directly
/// through `drift_flutter`'s web backend.
Future<MeridianDatabase> openMeridianDatabase() async {
  if (kIsWeb) {
    return MeridianDatabase(driftDatabase(name: 'meridian'));
  }

  IsolateNameServer.removePortNameMapping(meridianDriftPortName);

  final dbFolder = await getApplicationDocumentsDirectory();
  final dbPath = '${dbFolder.path}${Platform.pathSeparator}meridian.db';

  final isolate = await DriftIsolate.spawn(
    () => DatabaseConnection(NativeDatabase(File(dbPath))),
  );

  final registered = IsolateNameServer.registerPortWithName(
    isolate.connectPort,
    meridianDriftPortName,
  );
  if (!registered) {
    // The main-isolate DB still works, but the Android background isolate
    // won't find the shared port — background bulletin/transmission writes
    // would silently stop syncing. Surface it rather than failing quietly.
    debugPrint(
      'openMeridianDatabase: failed to register "$meridianDriftPortName" '
      'with IsolateNameServer — background DB sharing is disabled.',
    );
  }

  return MeridianDatabase.connect(await isolate.connect());
}

/// Look up the shared drift connect port and open a client connection.
///
/// Called from the background isolate (`MeridianConnectionTask`). Returns
/// `null` if no main-isolate registration is present — the caller should
/// fall back to its legacy SharedPreferences path until the main isolate
/// revives.
Future<MeridianDatabase?> lookupBackgroundDatabasePort() async {
  if (kIsWeb) return null;
  final port = IsolateNameServer.lookupPortByName(meridianDriftPortName);
  if (port == null) return null;
  final isolate = DriftIsolate.fromConnectPort(port);
  return MeridianDatabase.connect(await isolate.connect());
}
