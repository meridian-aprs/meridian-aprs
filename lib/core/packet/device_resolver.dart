/// Resolves a human-readable device or software name from APRS tocall fields
/// and Mic-E comment suffixes.
///
/// All methods are static. No state is held.
class DeviceResolver {
  DeviceResolver._();

  // Sorted longest-prefix-first so the first match wins.
  static const _tocallTable = [
    ('APZMAJ', 'Xastir'),
    ('APFII', 'iPhone app (APRS.fi)'),
    ('APKRAM', 'KRAMsoftware'),
    ('APAGW', 'AGWTracker'),
    ('APBM', 'BrandMeister gateway'),
    ('APHBL', 'HamBLNY'),
    ('APMI0', 'Micro-Trak RTG'),
    ('APAND', 'APRSdroid'),
    ('APOLU', 'OSCAR satellite'),
    ('APNL', 'D-Star island'),
    ('APAT', 'AnyTone'),
    ('APTT4', 'TinyTrak4'),
    ('APTT', 'TinyTrak'),
    ('APRX', 'aprx iGate'),
    ('APWW', 'UI-View32'),
    ('APDW', 'Dire Wolf'),
    ('APDR', 'APRSdroid'),
    ('APLM', 'WIDEn-n digipeater'),
    ('APMI', 'Micro-Trak'),
    ('APK0', 'Kenwood TH-D7A'),
    ('APK1', 'Kenwood TM-D700'),
    ('APXR', 'Xrouter'),
    ('APN3', 'Kantronics KPC-3'),
    ('APN9', 'Kantronics KPC-9612'),
    ('APNP', 'TNC2 clone'),
    ('APNT', 'TNT TNC'),
    ('APNW', 'WB4IHY TNC'),
    ('APNX', 'KPC3 clone'),
    ('APOA', 'Open APRS'),
    ('APHYA', 'Yaesu FT1D'),
    ('APOT', 'OpenTracker'),
    ('APRS', 'APRS (generic)'),
    ('APYE', 'Yaesu FT2D'),
    ('APY', 'Yaesu (FTM/FT-series)'),
  ];

  // Regex for valid generic > suffix: alphanumeric only, length 2-10.
  // Restricted to [A-Za-z0-9] to prevent false positives on user comments
  // that happen to contain '>'.  Device identifiers are always alphanumeric
  // in practice (e.g. FT3DR, FTM400, TINYTRK).
  static final _genericSuffixRe = RegExp(r'^[A-Za-z0-9]{2,10}$');

  // Regex for Yaesu FT3D series: trailing _\d (e.g. `_0`, `_1`).
  // Known limitation: this pattern will false-positive on user comments that
  // happen to end in `_0`–`_9` (e.g. "grid_0").  This is an accepted
  // trade-off given how rare such comment endings are in practice.
  static final _ft3dRe = RegExp(r'_\d$');

  /// Returns a human-readable device/software name for an APRS station,
  /// or null if the device cannot be identified.
  ///
  /// [tocall] is the destination field from the APRS header (e.g. "APDR16",
  /// "APK004"). Used for non-Mic-E packets.
  ///
  /// [micECommentSuffix] is the raw comment suffix extracted from a Mic-E
  /// packet AFTER stripping the telemetry prefix. Pass null for non-Mic-E
  /// packets.
  static String? resolve({String? tocall, String? micECommentSuffix}) {
    if (micECommentSuffix != null) {
      return _resolveMicESuffix(micECommentSuffix);
    }
    if (tocall != null && tocall.isNotEmpty) {
      return _resolveTocall(tocall);
    }
    return null;
  }

  static String? _resolveTocall(String tocall) {
    // Strip any trailing SSID (-N) before matching.
    final ssidIdx = tocall.lastIndexOf('-');
    final base = ssidIdx >= 0 ? tocall.substring(0, ssidIdx) : tocall;
    final upper = base.toUpperCase();

    for (final (prefix, device) in _tocallTable) {
      if (upper.startsWith(prefix)) return device;
    }
    return null;
  }

  static String? _resolveMicESuffix(String comment) {
    if (comment.isEmpty) return null;

    // Check in order — longest/most-specific suffixes first.
    if (comment.endsWith(']=')) return 'Kenwood TH-D72A';
    if (comment.endsWith(']\x22')) return 'Kenwood TM-D710';
    if (comment.endsWith(']')) return 'Kenwood (TH-D7x/TM-D7x)';
    if (comment.endsWith('^')) return 'Yaesu VX-8';
    if (comment.endsWith('~')) return 'Yaesu FT2D';
    if (_ft3dRe.hasMatch(comment)) return 'Yaesu FT3D series';

    // Generic > suffix: everything after the last >.
    final gtIdx = comment.lastIndexOf('>');
    if (gtIdx >= 0 && gtIdx < comment.length - 1) {
      final suffix = comment.substring(gtIdx + 1);
      if (_genericSuffixRe.hasMatch(suffix)) return suffix;
    }

    return null;
  }
}
