/// APRS identity constants for Meridian APRS.
library;

import '../../config/app_version.dart';

/// Meridian APRS identity constants.
class AprsIdentity {
  AprsIdentity._();

  /// Tocall derived from the app's major version number.
  ///
  /// Allocation: `APMDN?` by Hessu OH7LZB (aprs-deviceid registry, 2026-04-19).
  /// Wildcard convention (last character = major version digit):
  ///   APMDN0 = v0.x
  ///   APMDN1 = v1.x
  ///   APMDNN = vN.x thereafter
  ///   APMDNZ = reserved for dev/nightly build identification
  ///            (do not implement until signed-release detection is wired up)
  ///
  /// Bumping [kAppVersion] major digit in lib/config/app_version.dart
  /// automatically updates the tocall — no manual change needed here.
  static String get tocall {
    final major = int.tryParse(kAppVersion.split('.').first) ?? 0;
    return 'APMDN$major';
  }
}
