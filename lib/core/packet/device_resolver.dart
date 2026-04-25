/// Resolves a human-readable device or software name from APRS tocall fields
/// and Mic-E comment suffixes.
///
/// Call [loadFromJson] at app startup (after [rootBundle] is available) to
/// replace the built-in prefix table with the full aprs-deviceid registry.
/// Until [loadFromJson] is called, [_tocallTable] is used as a fallback.
library;

import 'dart:convert';

/// Resolves a human-readable device or software name from APRS tocall fields
/// and Mic-E comment suffixes.
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

  /// JSON-backed pattern list, loaded from the aprs-deviceid registry.
  ///
  /// Empty until [loadFromJson] is called; when empty, [_resolveTocall] falls
  /// back to [_tocallTable].
  static List<({RegExp pattern, String device})> _tocallPatterns = [];

  // Regex for Yaesu FT3D series: trailing _\d (e.g. `_0`, `_1`).
  // Known limitation: this pattern will false-positive on user comments that
  // happen to end in `_0`–`_9` (e.g. "grid_0").  This is an accepted
  // trade-off given how rare such comment endings are in practice.
  static final _ft3dRe = RegExp(r'_\d$');

  /// Loads the aprs-deviceid tocall registry from [jsonStr].
  ///
  /// Expected format: the `tocalls` object from `tocalls.dense.json`. Each
  /// key may contain wildcard characters:
  /// - `?` matches any single alphanumeric character (A-Z, 0-9).
  /// - `n` matches any single digit (0-9).
  /// - `*` matches any trailing characters.
  ///
  /// On any parse error the existing [_tocallPatterns] (or the hardcoded
  /// [_tocallTable] if not yet loaded) are preserved and no exception is thrown.
  static void loadFromJson(String jsonStr) {
    try {
      final dynamic decoded = json.decode(jsonStr);
      if (decoded is! Map<String, dynamic>) return;

      final dynamic tocallsRaw = decoded['tocalls'];
      if (tocallsRaw is! Map<String, dynamic>) return;

      final patterns = <({RegExp pattern, String device, int specificity})>[];

      for (final entry in tocallsRaw.entries) {
        final key = entry.key;
        final dynamic value = entry.value;
        if (value is! Map<String, dynamic>) continue;

        final String? model = value['model'] as String?;
        final String? vendor = value['vendor'] as String?;
        final device = (model != null && model.isNotEmpty)
            ? model
            : (vendor ?? '');
        if (device.isEmpty) continue;

        final regexStr = _keyToRegex(key);
        final re = RegExp('^$regexStr', caseSensitive: false);

        // Specificity: count of leading literal (non-wildcard) characters.
        // Higher = more specific = matched first.
        final specificity = _countLeadingLiterals(key);

        patterns.add((pattern: re, device: device, specificity: specificity));
      }

      // Sort: highest specificity first; within same specificity, longer key
      // first (more total characters = more constrained).
      patterns.sort((a, b) {
        final cmp = b.specificity.compareTo(a.specificity);
        return cmp;
      });

      _tocallPatterns = patterns
          .map((e) => (pattern: e.pattern, device: e.device))
          .toList();
    } catch (e) {
      // Malformed JSON or unexpected structure — keep existing patterns.
      // ignore: avoid_print
      print(
        'DeviceResolver.loadFromJson: parse error, keeping existing table: $e',
      );
    }
  }

  /// Resets the JSON-loaded pattern list, reverting to [_tocallTable].
  ///
  /// For use in tests only.
  static void resetForTesting() {
    _tocallPatterns = [];
  }

  /// Returns a human-readable device/software name for an APRS station,
  /// or null if the device cannot be identified.
  ///
  /// [tocall] is the destination field from the APRS header (e.g. "APDR16",
  /// "APK004"). Used for non-Mic-E packets.
  ///
  /// For Mic-E packets, pass either or both of:
  /// - [micEPrefix] — the single manufacturer-code byte at info position 9
  ///   (the byte right after the symbol-table char), if it is `>` or `]`.
  ///   These mark the legacy Kenwood family and combine with [micECommentSuffix]
  ///   to disambiguate D7A / D72A / D74 / D700 / D710 per APRS 1.0.1 ch.10
  ///   and aprs.org/aprs12/mic-e-types.txt.
  /// - [micECommentSuffix] — the comment text (with any trailing model byte
  ///   still attached) AFTER stripping telemetry/altitude. Used for the
  ///   modern Yaesu/Anytone suffix-anchored match (`^`, `~`, `_\d`) and as
  ///   the trailing-byte input for legacy Kenwood matching.
  static String? resolve({
    String? tocall,
    String? micEPrefix,
    String? micECommentSuffix,
  }) {
    if (micEPrefix != null || micECommentSuffix != null) {
      return _resolveMicE(prefix: micEPrefix, comment: micECommentSuffix ?? '');
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

    if (_tocallPatterns.isNotEmpty) {
      for (final entry in _tocallPatterns) {
        if (entry.pattern.hasMatch(upper)) return entry.device;
      }
      return null;
    }

    // Fallback: hardcoded prefix table.
    for (final (prefix, device) in _tocallTable) {
      if (upper.startsWith(prefix)) return device;
    }
    return null;
  }

  // Two-pass Mic-E device resolution.
  //
  // Pass 1 — legacy Kenwood (prefix + optional trailing byte):
  //   per aprs.org/aprs12/mic-e-types.txt, the Kenwood family identifies
  //   itself with a leading byte at info[9] and an optional trailing byte
  //   at the end of the comment. Both must agree.
  //
  // Pass 2 — modern (Yaesu/Anytone/Byonics) suffix-anchored matching.
  //   These radios all use the `\x60` (backtick) leading byte uniformly
  //   and discriminate purely on the trailing byte(s).
  static String? _resolveMicE({
    required String? prefix,
    required String comment,
  }) {
    // Pass 1 — Kenwood legacy.
    if (prefix == '>') {
      if (comment.endsWith('=')) return 'Kenwood TH-D72A';
      if (comment.endsWith('^')) return 'Kenwood TH-D74';
      return 'Kenwood TH-D7A';
    }
    if (prefix == ']') {
      if (comment.endsWith('=')) return 'Kenwood TM-D710';
      return 'Kenwood TM-D700';
    }

    // Pass 2 — Yaesu / Anytone / Byonics suffix matching.
    if (comment.isEmpty) return null;
    if (comment.endsWith('^')) return 'Yaesu VX-8';
    if (comment.endsWith('~')) return 'Yaesu FT2D';
    if (_ft3dRe.hasMatch(comment)) return 'Yaesu FT3D series';
    return null;
  }

  /// Converts an aprs-deviceid key to a regex string fragment.
  ///
  /// Wildcard mapping:
  /// - `?` → `[A-Z0-9]` (any single alphanumeric)
  /// - `n` → `[0-9]` (any single digit)
  /// - `*` → `.*` (any trailing characters)
  /// - All other characters are regex-escaped.
  static String _keyToRegex(String key) {
    final buf = StringBuffer();
    for (var i = 0; i < key.length; i++) {
      final ch = key[i];
      if (ch == '?') {
        buf.write('[A-Z0-9]');
      } else if (ch == 'n') {
        buf.write('[0-9]');
      } else if (ch == '*') {
        buf.write('.*');
      } else {
        // Escape any regex metacharacter.
        buf.write(RegExp.escape(ch));
      }
    }
    return buf.toString();
  }

  /// Returns the count of leading literal characters (before any wildcard).
  ///
  /// Used to rank more-specific patterns higher than wildcard patterns of the
  /// same key length.
  static int _countLeadingLiterals(String key) {
    var count = 0;
    for (var i = 0; i < key.length; i++) {
      final ch = key[i];
      if (ch == '?' || ch == 'n' || ch == '*') break;
      count++;
    }
    return count;
  }
}
