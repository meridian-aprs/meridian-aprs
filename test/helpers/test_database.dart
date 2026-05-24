import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:meridian_aprs/database/meridian_database.dart';

bool _suppressedWarnings = false;

/// Build an in-memory `MeridianDatabase` for use in unit and widget tests.
///
/// Tests routinely construct multiple databases (per-test setUp, or one for
/// the SUT plus a second for a regression fixture). drift warns about this
/// by default — silence the warning once.
MeridianDatabase buildTestDatabase() {
  if (!_suppressedWarnings) {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    _suppressedWarnings = true;
  }
  return MeridianDatabase(NativeDatabase.memory());
}
