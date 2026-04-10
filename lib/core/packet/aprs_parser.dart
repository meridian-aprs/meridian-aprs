import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../ax25/ax25_parser.dart';
import 'aprs_packet.dart';
import 'device_resolver.dart';

/// Decoded csT (course/speed/altitude) triplet from a compressed position.
///
/// [comment] is the remaining info string after the three csT bytes have been
/// consumed.  All numeric fields are null when not present or not applicable.
class _CsT {
  const _CsT({this.course, this.speed, this.altitude, required this.comment});
  final int? course;
  final double? speed;
  final double? altitude;
  final String comment;
}

/// Full APRS packet parser.
///
/// [parse] accepts an APRS-IS text line and returns a typed [AprsPacket].
/// It never throws — malformed input always yields [UnknownPacket].
///
/// [parseFrame] accepts raw AX.25 frame bytes (stub; APRS-IS is the current
/// use case). Returns [UnknownPacket] for now.
class AprsParser {
  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Parse one APRS-IS line.
  ///
  /// Format: `SOURCE>DEST,PATH:INFO`
  ///
  /// Supply [receivedAt] to override the default of [DateTime.now]. Useful
  /// when restoring persisted packets that already have a known receive time.
  AprsPacket parse(
    String line, {
    PacketSource transportSource = PacketSource.aprsIs,
    DateTime? receivedAt,
  }) {
    // Ignore blank lines and server comment lines.
    if (line.isEmpty || line.startsWith('#')) {
      return _unknown(
        line,
        '',
        '',
        [],
        'Server comment or empty line',
        transportSource: transportSource,
      );
    }

    // Split header from info field at the first colon.
    final colonIdx = line.indexOf(':');
    if (colonIdx < 0 || colonIdx + 1 > line.length) {
      return _unknown(
        line,
        '',
        '',
        [],
        'No colon separator found',
        transportSource: transportSource,
      );
    }

    final header = line.substring(0, colonIdx);
    final info = colonIdx + 1 < line.length ? line.substring(colonIdx + 1) : '';

    // Parse header: SOURCE>DEST,p1,p2,...
    final gtIdx = header.indexOf('>');
    if (gtIdx <= 0) {
      return _unknown(
        line,
        '',
        '',
        [],
        'No > in header',
        transportSource: transportSource,
      );
    }
    final source = header.substring(0, gtIdx);
    final destAndPath = header.substring(gtIdx + 1);
    final pathParts = destAndPath.split(',');
    final destination = pathParts.isNotEmpty ? pathParts.first : '';
    final path = pathParts.length > 1 ? pathParts.sublist(1) : <String>[];

    if (info.isEmpty) {
      return _unknown(
        line,
        source,
        destination,
        path,
        'Empty info field',
        transportSource: transportSource,
      );
    }

    final dti = info[0];
    final now = receivedAt ?? DateTime.now().toUtc();

    try {
      return _dispatch(
        dti: dti,
        info: info,
        rawLine: line,
        source: source,
        destination: destination,
        path: path,
        receivedAt: now,
        transportSource: transportSource,
      );
    } catch (_) {
      // Belt-and-suspenders: never propagate exceptions.
      return UnknownPacket(
        rawLine: line,
        source: source,
        destination: destination,
        path: path,
        receivedAt: now,
        transportSource: transportSource,
        reason: 'Unhandled parse exception',
        rawInfo: info,
      );
    }
  }

  /// Parse raw AX.25 frame bytes.
  ///
  /// Stub implementation — returns [UnknownPacket] until AX.25 framing support
  /// is added in a future milestone.
  AprsPacket parseFrame(
    Uint8List frameBytes, {
    PacketSource transportSource = PacketSource.aprsIs,
  }) {
    final result = const Ax25Parser().parseFrame(frameBytes);
    if (result is Ax25Err) {
      return UnknownPacket(
        rawLine: '',
        source: '',
        destination: '',
        path: const [],
        receivedAt: DateTime.now().toUtc(),
        transportSource: transportSource,
        reason: 'AX.25 decode failed: ${result.reason}',
      );
    }
    final frame = (result as Ax25Ok).frame;
    // Strip trailing CR/LF that some TNCs (e.g. Mobilinkd, Direwolf) append to
    // the AX.25 info field.  Without this, message IDs like '003\r' never match
    // outgoing wireIds and ACK handling silently fails.
    final infoStr = latin1.decode(frame.info).trimRight();
    final pathStr = frame.pathString.isEmpty ? '' : ',${frame.pathString}';
    final reconstructed =
        '${frame.source}>${frame.destination}$pathStr:$infoStr';
    return parse(reconstructed, transportSource: transportSource);
  }

  // ---------------------------------------------------------------------------
  // DTI dispatch
  // ---------------------------------------------------------------------------

  AprsPacket _dispatch({
    required String dti,
    required String info,
    required String rawLine,
    required String source,
    required String destination,
    required List<String> path,
    required DateTime receivedAt,
    required PacketSource transportSource,
  }) {
    switch (dti) {
      // Position without timestamp — no messaging (!) or messaging (=)
      case '!':
      case '=':
        return _parsePosition(
          info: info,
          rawLine: rawLine,
          source: source,
          destination: destination,
          path: path,
          receivedAt: receivedAt,
          hasTimestamp: false,
          hasMessaging: dti == '=',
          transportSource: transportSource,
        );

      // Position with timestamp — no messaging (/) or messaging (@)
      case '/':
      case '@':
        return _parsePosition(
          info: info,
          rawLine: rawLine,
          source: source,
          destination: destination,
          path: path,
          receivedAt: receivedAt,
          hasTimestamp: true,
          hasMessaging: dti == '@',
          transportSource: transportSource,
        );

      case ';':
        return _parseObject(
          info: info,
          rawLine: rawLine,
          source: source,
          destination: destination,
          path: path,
          receivedAt: receivedAt,
          transportSource: transportSource,
        );

      case ')':
        return _parseItem(
          info: info,
          rawLine: rawLine,
          source: source,
          destination: destination,
          path: path,
          receivedAt: receivedAt,
          transportSource: transportSource,
        );

      case ':':
        return _parseMessage(
          info: info,
          rawLine: rawLine,
          source: source,
          destination: destination,
          path: path,
          receivedAt: receivedAt,
          transportSource: transportSource,
        );

      case '_':
        return _parseWeather(
          info: info,
          rawLine: rawLine,
          source: source,
          destination: destination,
          path: path,
          receivedAt: receivedAt,
          transportSource: transportSource,
        );

      case '>':
        return _parseStatus(
          info: info,
          rawLine: rawLine,
          source: source,
          destination: destination,
          path: path,
          receivedAt: receivedAt,
          transportSource: transportSource,
        );

      // Mic-E
      case '`':
      case "'":
        return _parseMicE(
          info: info,
          rawLine: rawLine,
          source: source,
          destination: destination,
          path: path,
          receivedAt: receivedAt,
          transportSource: transportSource,
        );

      // Telemetry — parsed as Unknown for now (v0.2 scope)
      case 'T':
        return UnknownPacket(
          rawLine: rawLine,
          source: source,
          destination: destination,
          path: path,
          receivedAt: receivedAt,
          transportSource: transportSource,
          reason: 'Telemetry not yet implemented',
          rawInfo: info,
        );

      default:
        return _unknown(
          rawLine,
          source,
          destination,
          path,
          'Unrecognised DTI: $dti',
          rawInfo: info,
          transportSource: transportSource,
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Position parsing
  // ---------------------------------------------------------------------------

  // Uncompressed position regex.
  // Groups: (lat DDMM.HH)(N|S)(symTable)(lon DDDMM.HH)(E|W)(symCode)(comment)
  static final _uncompressedPosRe = RegExp(
    r'^(\d{4}\.\d{2})(N|S)(.)(\d{5}\.\d{2})(E|W)(.)(.*)$',
    dotAll: true,
  );

  // Course/speed/altitude comment extensions.
  // Course/speed: "CCC/SSS" — 3-digit course, slash, 3-digit speed (knots).
  static final _courseSpeedRe = RegExp(r'^(\d{3})/(\d{3})');

  // Altitude: "/A=XXXXXX" anywhere in comment (feet).
  static final _altRe = RegExp(r'/A=(\d+)');

  // DHM timestamp: DDHHMMz (UTC) or DDHMM/ (local variant, per Dire Wolf).
  // The 'h' suffix is NOT a valid DHM suffix — it belongs to the HMS format.
  static final _dhmRe = RegExp(r'^(\d{2})(\d{2})(\d{2})[z/]$');

  // HMS timestamp: HHMMSSh — hour/minute/second (local, treated as UTC).
  static final _hmsRe = RegExp(r'^(\d{2})(\d{2})(\d{2})h$');

  AprsPacket _parsePosition({
    required String info,
    required String rawLine,
    required String source,
    required String destination,
    required List<String> path,
    required DateTime receivedAt,
    required bool hasTimestamp,
    required bool hasMessaging,
    required PacketSource transportSource,
  }) {
    // info[0] is the DTI. After that, optionally a 7-char timestamp, then position.
    String posStr;
    DateTime? packetTimestamp;

    if (hasTimestamp) {
      // Need at least DTI + 7 timestamp chars + something for position.
      if (info.length < 9) {
        return _unknown(
          rawLine,
          source,
          destination,
          path,
          'Timestamped position too short',
          rawInfo: info,
          transportSource: transportSource,
        );
      }
      final tsStr = info.substring(1, 8); // 7 chars
      packetTimestamp = _parseTimestamp(tsStr, receivedAt);
      posStr = info.substring(8);
    } else {
      posStr = info.substring(1);
    }

    if (posStr.isEmpty) {
      return _unknown(
        rawLine,
        source,
        destination,
        path,
        'No position data after DTI/timestamp',
        rawInfo: info,
        transportSource: transportSource,
      );
    }

    // Detect compressed vs uncompressed.
    // Compressed position: posStr[0] is the symbol table character (/ \ or
    // overlay), posStr[1..4] are 4 base-91 lat chars (ASCII 33-124),
    // posStr[5..8] are 4 base-91 lon chars, posStr[9] is symbol code.
    // The APRS spec says compressed lat/lon chars are in range [33, 122]
    // (printable ASCII except space and '{'-'~'). We use the presence of
    // base-91 chars to distinguish. A quick heuristic: if posStr[1] is a
    // digit it's uncompressed lat (DDmm.mm format always starts with a digit).
    final bool isCompressed =
        posStr.length >= 10 && !_isUncompressedPos(posStr);

    if (isCompressed) {
      return _parseCompressedPosition(
        posStr: posStr,
        info: info,
        rawLine: rawLine,
        source: source,
        destination: destination,
        path: path,
        receivedAt: receivedAt,
        hasMessaging: hasMessaging,
        packetTimestamp: packetTimestamp,
        transportSource: transportSource,
      );
    } else {
      return _parseUncompressedPosition(
        posStr: posStr,
        info: info,
        rawLine: rawLine,
        source: source,
        destination: destination,
        path: path,
        receivedAt: receivedAt,
        hasMessaging: hasMessaging,
        packetTimestamp: packetTimestamp,
        transportSource: transportSource,
      );
    }
  }

  /// Heuristic to distinguish uncompressed from compressed position strings.
  /// Uncompressed lat always begins with a digit (DDMM.HH pattern).
  bool _isUncompressedPos(String posStr) {
    if (posStr.isEmpty) return false;
    // Skip the symbol table char at index 0 for compressed; for uncompressed
    // the entire posStr is the position data starting with digit.
    // Uncompressed posStr starts with digits like '4903.50N...'
    return posStr[0].codeUnitAt(0) >= 0x30 && posStr[0].codeUnitAt(0) <= 0x39;
  }

  AprsPacket _parseUncompressedPosition({
    required String posStr,
    required String info,
    required String rawLine,
    required String source,
    required String destination,
    required List<String> path,
    required DateTime receivedAt,
    required bool hasMessaging,
    required DateTime? packetTimestamp,
    required PacketSource transportSource,
  }) {
    final m = _uncompressedPosRe.firstMatch(posStr);
    if (m == null) {
      return _unknown(
        rawLine,
        source,
        destination,
        path,
        'Uncompressed position regex did not match',
        rawInfo: info,
        transportSource: transportSource,
      );
    }

    final lat = _ddmm(m.group(1)!, isLat: true) * (m.group(2) == 'S' ? -1 : 1);
    final lon = _ddmm(m.group(4)!, isLat: false) * (m.group(5) == 'W' ? -1 : 1);
    final symbolTable = m.group(3)!;
    final symbolCode = m.group(6)!;
    var comment = m.group(7)!;

    // Extract course/speed from beginning of comment.
    int? course;
    double? speed;
    final csMatch = _courseSpeedRe.firstMatch(comment);
    if (csMatch != null) {
      final c = int.tryParse(csMatch.group(1)!);
      final s = int.tryParse(csMatch.group(2)!);
      if (c != null && s != null && !(c == 0 && s == 0)) {
        course = c;
        speed = s.toDouble(); // knots
        comment = comment.substring(csMatch.end);
      }
    }

    // Extract altitude from comment.
    double? altitude;
    final altMatch = _altRe.firstMatch(comment);
    if (altMatch != null) {
      final feet = int.tryParse(altMatch.group(1)!);
      if (feet != null) altitude = feet.toDouble();
      // Strip the altitude extension from the comment display.
      comment = comment.replaceFirst(_altRe, '').trim();
    }

    return PositionPacket(
      rawLine: rawLine,
      source: source,
      destination: destination,
      path: path,
      receivedAt: receivedAt,
      transportSource: transportSource,
      lat: lat,
      lon: lon,
      symbolTable: symbolTable,
      symbolCode: symbolCode,
      comment: comment,
      altitude: altitude,
      course: course,
      speed: speed,
      hasMessaging: hasMessaging,
      timestamp: packetTimestamp,
      device: DeviceResolver.resolve(tocall: destination),
    );
  }

  AprsPacket _parseCompressedPosition({
    required String posStr,
    required String info,
    required String rawLine,
    required String source,
    required String destination,
    required List<String> path,
    required DateTime receivedAt,
    required bool hasMessaging,
    required DateTime? packetTimestamp,
    required PacketSource transportSource,
  }) {
    // Compressed format (APRS spec chapter 9):
    // posStr: symTable(1) + latChars(4) + lonChars(4) + symCode(1) + csT(3) + comment
    // Each base-91 group: value = (c1-33)*91^3 + (c2-33)*91^2 + (c3-33)*91 + (c4-33)
    if (posStr.length < 10) {
      return _unknown(
        rawLine,
        source,
        destination,
        path,
        'Compressed position string too short',
        rawInfo: info,
        transportSource: transportSource,
      );
    }

    final symbolTable = posStr[0];
    final latChars = posStr.substring(1, 5);
    final lonChars = posStr.substring(5, 9);
    final symbolCode = posStr[9];
    final remainder = posStr.length > 10 ? posStr.substring(10) : '';

    // Decode base-91 lat: L = 90 - (value / 380926)  degrees
    final latVal = _base91Decode4(latChars);
    final lonVal = _base91Decode4(lonChars);
    if (latVal == null || lonVal == null) {
      return _unknown(
        rawLine,
        source,
        destination,
        path,
        'Invalid base-91 encoding in compressed position',
        rawInfo: info,
        transportSource: transportSource,
      );
    }

    final lat = 90.0 - latVal / 380926.0;
    final lon = -180.0 + lonVal / 190463.0;

    // Parse optional csT bytes (course/speed/altitude) via shared helper.
    final cst = _parseCsT(remainder);
    final int? course = cst.course;
    final double? speed = cst.speed;
    final double? altitude = cst.altitude;
    final String comment = cst.comment;

    return PositionPacket(
      rawLine: rawLine,
      source: source,
      destination: destination,
      path: path,
      receivedAt: receivedAt,
      transportSource: transportSource,
      lat: lat,
      lon: lon,
      symbolTable: symbolTable,
      symbolCode: symbolCode,
      comment: comment,
      altitude: altitude,
      course: course,
      speed: speed,
      hasMessaging: hasMessaging,
      timestamp: packetTimestamp,
      device: DeviceResolver.resolve(tocall: destination),
    );
  }

  /// Parse the optional csT (course/speed/altitude) triplet from the
  /// [remainder] string that follows the symbol code in a compressed position.
  ///
  /// Per APRS 1.0.1 ch.9 p.39–40:
  ///   - c byte == 0x20 (space): csT bytes carry no data — skip 3 bytes.
  ///   - c byte value (codeUnit - 33) in range 0–89: course/speed, unless the
  ///     T byte indicates GGA source (bits 4–3 of T-33 == 2), in which case
  ///     altitude interpretation takes priority.
  ///   - c byte value == 90 (`{`): radio range — skip 3 bytes, no data.
  ///   - T byte NMEA source (bits 4–3 of T-33) == 2 (GGA): altitude in feet
  ///     = 1.002^(cByte * 91 + sByte).
  ///
  /// Returns a [_CsT] record with decoded values and the post-csT comment.
  _CsT _parseCsT(String remainder) {
    if (remainder.isEmpty) {
      return _CsT(comment: '');
    }
    // Space c byte: csT bytes present but carry no data — skip 3 bytes.
    if (remainder.codeUnitAt(0) == 0x20) {
      return _CsT(comment: remainder.length > 3 ? remainder.substring(3) : '');
    }
    if (remainder.length >= 3) {
      final cByte = remainder[0].codeUnitAt(0) - 33;
      final sByte = remainder[1].codeUnitAt(0) - 33;
      final tByte = remainder[2].codeUnitAt(0) - 33;
      final afterCsT = remainder.length > 3 ? remainder.substring(3) : '';

      // Radio range: c byte value == 90 (char '{'). Skip 3 bytes, no data.
      if (cByte == 90) {
        return _CsT(comment: afterCsT);
      }

      // GGA altitude takes priority when NMEA source bits 4–3 of T byte == 2.
      // This is mutually exclusive with course/speed in practice.
      final nmeasSource = (tByte >> 3) & 0x3;
      if (nmeasSource == 2) {
        // GGA altitude: 1.002^(cByte*91 + sByte) feet (APRS 1.0.1 ch.9 p.40).
        final altitude = pow(1.002, cByte * 91 + sByte).toDouble();
        return _CsT(altitude: altitude, comment: afterCsT);
      }

      // Course/speed: c byte value 0–89.
      if (cByte >= 0 && cByte <= 89) {
        final c = cByte * 4;
        int? course;
        double? speed;
        if (cByte != 0 || sByte != 0) {
          course = c == 360 ? 0 : c;
          speed = pow(1.08, sByte).toDouble() - 1;
        }
        return _CsT(course: course, speed: speed, comment: afterCsT);
      }
    }
    return _CsT(comment: remainder.length > 3 ? remainder.substring(3) : '');
  }

  /// Decode 4 base-91 characters to an integer value.
  int? _base91Decode4(String s) {
    if (s.length != 4) return null;
    int v = 0;
    for (int i = 0; i < 4; i++) {
      final c = s.codeUnitAt(i) - 33;
      if (c < 0 || c > 90) return null;
      v = v * 91 + c;
    }
    return v;
  }

  // ---------------------------------------------------------------------------
  // Object parsing  (DTI: ;)
  // ---------------------------------------------------------------------------

  // Object format: ;NNNNNNNNN*DDHHMMzDDMM.HHN/DDDMM.HHWsymcomment
  // or with killed: ;NNNNNNNNN_timestamp...
  // Name is exactly 9 characters (chars 1-9 of info field, after DTI).
  AprsPacket _parseObject({
    required String info,
    required String rawLine,
    required String source,
    required String destination,
    required List<String> path,
    required DateTime receivedAt,
    required PacketSource transportSource,
  }) {
    // Minimum: ; + 9 name + alive/killed + 7 timestamp + position (~18 chars)
    if (info.length < 18) {
      return _unknown(
        rawLine,
        source,
        destination,
        path,
        'Object packet too short',
        rawInfo: info,
        transportSource: transportSource,
      );
    }

    final objectName = info.substring(1, 10).trimRight();
    final aliveChar = info[10]; // '*' = alive, '_' = killed
    final isAlive = aliveChar == '*';

    // After alive/killed char: 7-char timestamp + position
    if (info.length < 18) {
      return _unknown(
        rawLine,
        source,
        destination,
        path,
        'Object packet missing timestamp/position',
        rawInfo: info,
        transportSource: transportSource,
      );
    }

    // Timestamp is chars 11-17 (7 chars), position starts at 18.
    final posStr = info.substring(18);
    final m = _uncompressedPosRe.firstMatch(posStr);
    if (m == null) {
      // Try compressed
      return _tryObjectCompressed(
        posStr: posStr,
        objectName: objectName,
        isAlive: isAlive,
        rawLine: rawLine,
        source: source,
        destination: destination,
        path: path,
        receivedAt: receivedAt,
        info: info,
        transportSource: transportSource,
      );
    }

    final lat = _ddmm(m.group(1)!, isLat: true) * (m.group(2) == 'S' ? -1 : 1);
    final lon = _ddmm(m.group(4)!, isLat: false) * (m.group(5) == 'W' ? -1 : 1);

    return ObjectPacket(
      rawLine: rawLine,
      source: source,
      destination: destination,
      path: path,
      receivedAt: receivedAt,
      transportSource: transportSource,
      objectName: objectName,
      lat: lat,
      lon: lon,
      symbolTable: m.group(3)!,
      symbolCode: m.group(6)!,
      comment: m.group(7)!,
      isAlive: isAlive,
      device: DeviceResolver.resolve(tocall: destination),
    );
  }

  AprsPacket _tryObjectCompressed({
    required String posStr,
    required String objectName,
    required bool isAlive,
    required String rawLine,
    required String source,
    required String destination,
    required List<String> path,
    required DateTime receivedAt,
    required String info,
    required PacketSource transportSource,
  }) {
    if (posStr.length < 10) {
      return _unknown(
        rawLine,
        source,
        destination,
        path,
        'Object compressed position too short',
        rawInfo: info,
        transportSource: transportSource,
      );
    }
    final symbolTable = posStr[0];
    final latChars = posStr.substring(1, 5);
    final lonChars = posStr.substring(5, 9);
    final symbolCode = posStr[9];
    final remainder = posStr.length > 10 ? posStr.substring(10) : '';

    final latVal = _base91Decode4(latChars);
    final lonVal = _base91Decode4(lonChars);
    if (latVal == null || lonVal == null) {
      return _unknown(
        rawLine,
        source,
        destination,
        path,
        'Object compressed position decode failed',
        rawInfo: info,
        transportSource: transportSource,
      );
    }

    // Parse csT bytes so they are not included in the comment.
    final cst = _parseCsT(remainder);

    return ObjectPacket(
      rawLine: rawLine,
      source: source,
      destination: destination,
      path: path,
      receivedAt: receivedAt,
      transportSource: transportSource,
      objectName: objectName,
      lat: 90.0 - latVal / 380926.0,
      lon: -180.0 + lonVal / 190463.0,
      symbolTable: symbolTable,
      symbolCode: symbolCode,
      comment: cst.comment,
      isAlive: isAlive,
      device: DeviceResolver.resolve(tocall: destination),
    );
  }

  // ---------------------------------------------------------------------------
  // Item parsing  (DTI: ))
  // ---------------------------------------------------------------------------

  // Item format: )NAME!position  or  )NAME_position (killed)
  // Name is 3-9 chars, terminated by '!' (alive) or '_' (killed).
  AprsPacket _parseItem({
    required String info,
    required String rawLine,
    required String source,
    required String destination,
    required List<String> path,
    required DateTime receivedAt,
    required PacketSource transportSource,
  }) {
    if (info.length < 5) {
      return _unknown(
        rawLine,
        source,
        destination,
        path,
        'Item packet too short',
        rawInfo: info,
        transportSource: transportSource,
      );
    }

    // Find the alive/killed delimiter ('!' or '_') after the DTI.
    final nameField = info.substring(1);
    int delimIdx = -1;
    bool isAlive = true;
    for (int i = 3; i < nameField.length && i <= 9; i++) {
      if (nameField[i] == '!' || nameField[i] == '_') {
        delimIdx = i;
        isAlive = nameField[i] == '!';
        break;
      }
    }
    if (delimIdx < 0) {
      return _unknown(
        rawLine,
        source,
        destination,
        path,
        'Item name delimiter not found',
        rawInfo: info,
        transportSource: transportSource,
      );
    }

    final itemName = nameField.substring(0, delimIdx).trimRight();
    final posStr = nameField.substring(delimIdx + 1);

    final m = _uncompressedPosRe.firstMatch(posStr);
    if (m == null) {
      return _unknown(
        rawLine,
        source,
        destination,
        path,
        'Item position parse failed',
        rawInfo: info,
        transportSource: transportSource,
      );
    }

    final lat = _ddmm(m.group(1)!, isLat: true) * (m.group(2) == 'S' ? -1 : 1);
    final lon = _ddmm(m.group(4)!, isLat: false) * (m.group(5) == 'W' ? -1 : 1);

    return ItemPacket(
      rawLine: rawLine,
      source: source,
      destination: destination,
      path: path,
      receivedAt: receivedAt,
      transportSource: transportSource,
      itemName: itemName,
      lat: lat,
      lon: lon,
      symbolTable: m.group(3)!,
      symbolCode: m.group(6)!,
      comment: m.group(7)!,
      isAlive: isAlive,
      device: DeviceResolver.resolve(tocall: destination),
    );
  }

  // ---------------------------------------------------------------------------
  // Message parsing  (DTI: :)
  // ---------------------------------------------------------------------------

  // Message format: :ADDRESSEE :message text{id}
  // Addressee is exactly 9 chars (space-padded), followed by ':', then message.
  // Optional message ID is the last '{NNN}' suffix.
  AprsPacket _parseMessage({
    required String info,
    required String rawLine,
    required String source,
    required String destination,
    required List<String> path,
    required DateTime receivedAt,
    required PacketSource transportSource,
  }) {
    // info[0] is ':', addressee is info[1..9], info[10] must be ':'.
    if (info.length < 11 || info[10] != ':') {
      return _unknown(
        rawLine,
        source,
        destination,
        path,
        'Message format invalid (need :XXXXXXXXX:)',
        rawInfo: info,
        transportSource: transportSource,
      );
    }

    final addressee = info.substring(1, 10).trim();
    var messageText = info.substring(11);

    // Extract optional message ID: '{NNN' suffix (no closing brace per spec).
    String? messageId;
    final idIdx = messageText.lastIndexOf('{');
    if (idIdx >= 0) {
      messageId = messageText.substring(idIdx + 1);
      messageText = messageText.substring(0, idIdx);
    }

    // Detect ACK/REJ: per APRS spec §14, these are always lowercase 'ack'/'rej'.
    // Case-sensitive match only — 'ACK' or 'REJ' in user text must not be
    // misidentified as protocol control packets.
    if (messageId == null && messageText.startsWith('ack')) {
      final ackId = messageText.length > 3 ? messageText.substring(3) : '';
      return MessagePacket(
        rawLine: rawLine,
        source: source,
        destination: destination,
        path: path,
        receivedAt: receivedAt,
        transportSource: transportSource,
        addressee: addressee,
        message: messageText,
        messageId: ackId.isEmpty ? null : ackId,
        isAck: true,
      );
    }
    if (messageId == null && messageText.startsWith('rej')) {
      final rejId = messageText.length > 3 ? messageText.substring(3) : '';
      return MessagePacket(
        rawLine: rawLine,
        source: source,
        destination: destination,
        path: path,
        receivedAt: receivedAt,
        transportSource: transportSource,
        addressee: addressee,
        message: messageText,
        messageId: rejId.isEmpty ? null : rejId,
        isRej: true,
      );
    }

    return MessagePacket(
      rawLine: rawLine,
      source: source,
      destination: destination,
      path: path,
      receivedAt: receivedAt,
      transportSource: transportSource,
      addressee: addressee,
      message: messageText,
      messageId: messageId?.isEmpty == true ? null : messageId,
    );
  }

  // ---------------------------------------------------------------------------
  // Weather parsing  (DTI: _)
  // ---------------------------------------------------------------------------

  // Standalone weather report: _MMDDHHMMcCCCsSSSgGGGtTTTrRRRpPPPPhhBBBBB
  // Field codes: c=wind dir, s=sustained wind, g=gust, t=temp, r=rain/hr,
  //              p=rain/24h, h=humidity, b=baro pressure
  static final _weatherFieldRe = RegExp(
    r'c(\d{3})|s(\d{3})|g(\d{3})|t(-?\d{3})|r(\d{3})|p(\d{3})|P(\d{3})|h(\d{2})|b(\d{5})',
  );

  AprsPacket _parseWeather({
    required String info,
    required String rawLine,
    required String source,
    required String destination,
    required List<String> path,
    required DateTime receivedAt,
    required PacketSource transportSource,
  }) {
    // Skip DTI and 8-char timestamp (MMDDhhmm).
    // Some implementations omit the timestamp; handle both.
    final weatherData = info.length > 9 ? info.substring(9) : info.substring(1);

    int? windDir;
    double? windSpeed;
    double? windGust;
    double? temperature;
    int? humidity;
    double? pressure;
    double? rainfall1h;
    double? rainfall24h;
    double? rainSinceMidnight;

    for (final m in _weatherFieldRe.allMatches(weatherData)) {
      if (m.group(1) != null) {
        windDir = int.tryParse(m.group(1)!);
      } else if (m.group(2) != null) {
        windSpeed = double.tryParse(m.group(2)!);
      } else if (m.group(3) != null) {
        windGust = double.tryParse(m.group(3)!);
      } else if (m.group(4) != null) {
        temperature = double.tryParse(m.group(4)!);
      } else if (m.group(5) != null) {
        rainfall1h = double.tryParse(m.group(5)!);
      } else if (m.group(6) != null) {
        rainfall24h = double.tryParse(m.group(6)!);
      } else if (m.group(7) != null) {
        // 'P' field: rainfall since midnight, in hundredths of an inch.
        rainSinceMidnight = double.tryParse(m.group(7)!);
      } else if (m.group(8) != null) {
        humidity = int.tryParse(m.group(8)!);
      } else if (m.group(9) != null) {
        final raw = int.tryParse(m.group(9)!);
        if (raw != null) pressure = raw / 10.0; // tenths of mb → mb
      }
    }

    return WeatherPacket(
      rawLine: rawLine,
      source: source,
      destination: destination,
      path: path,
      receivedAt: receivedAt,
      transportSource: transportSource,
      temperature: temperature,
      humidity: humidity,
      pressure: pressure,
      windSpeed: windSpeed,
      windDirection: windDir,
      windGust: windGust,
      rainfall1h: rainfall1h,
      rainfall24h: rainfall24h,
      rainSinceMidnight: rainSinceMidnight,
    );
  }

  // ---------------------------------------------------------------------------
  // Status parsing  (DTI: >)
  // ---------------------------------------------------------------------------

  // Status format: >status text  or  >DHMzstatus text  (optional timestamp)
  AprsPacket _parseStatus({
    required String info,
    required String rawLine,
    required String source,
    required String destination,
    required List<String> path,
    required DateTime receivedAt,
    required PacketSource transportSource,
  }) {
    var statusText = info.substring(1); // drop DTI
    DateTime? packetTimestamp;

    // Optional 7-char DHM timestamp at the beginning.
    if (statusText.length >= 7) {
      final possibleTs = statusText.substring(0, 7);
      final tsResult = _parseTimestamp(possibleTs, receivedAt);
      if (tsResult != null) {
        packetTimestamp = tsResult;
        statusText = statusText.substring(7);
      }
    }

    return StatusPacket(
      rawLine: rawLine,
      source: source,
      destination: destination,
      path: path,
      receivedAt: receivedAt,
      transportSource: transportSource,
      status: statusText,
      timestamp: packetTimestamp,
    );
  }

  // ---------------------------------------------------------------------------
  // Mic-E parsing  (DTI: ` or ')
  // ---------------------------------------------------------------------------

  // Mic-E is one of the most complex APRS formats. The latitude, N/S, E/W
  // longitude offset, and message bits are encoded in the 6-char AX.25
  // destination field. The info field encodes longitude, speed, course, and
  // symbol. Reference: APRS spec chapter 10, aprslib mic_e.py.
  //
  // Destination encoding per char:
  //   char 0-5 of destination (uppercase, digits, space)
  //   Each char encodes one nibble of lat and one message/flag bit.
  //
  // The destination callsign for Mic-E is NOT the usual APRS destination —
  // it carries encoded data. We receive it already decoded from the APRS-IS
  // header parser as [destination].

  static const _micEMessages = [
    'Emergency', // 0b000
    'Priority', // 0b001
    'Special', // 0b010
    'Committed', // 0b011
    'Returning', // 0b100
    'In Service', // 0b101
    'En Route', // 0b110
    'Off Duty', // 0b111
  ];

  static const _micECustomMessages = [
    'Emergency', // 0b000 — Emergency regardless of table
    'Custom-0', // 0b001
    'Custom-1', // 0b010
    'Custom-2', // 0b011
    'Custom-3', // 0b100
    'Custom-4', // 0b101
    'Custom-5', // 0b110
    'Custom-6', // 0b111
  ];

  AprsPacket _parseMicE({
    required String info,
    required String rawLine,
    required String source,
    required String destination,
    required List<String> path,
    required DateTime receivedAt,
    required PacketSource transportSource,
  }) {
    // Destination must be at least 6 chars.
    if (destination.length < 6 || info.length < 9) {
      return _unknown(
        rawLine,
        source,
        destination,
        path,
        'Mic-E packet too short',
        rawInfo: info,
        transportSource: transportSource,
      );
    }

    // Decode latitude and message bits from destination chars 0-5.
    // Each char encodes one BCD digit of latitude (0-9) and flags.
    // Three character sets encode a digit with message bit set:
    //   'A'-'J' (0x41-0x4A): custom message bit, digits 0-9
    //   'P'-'Y' (0x50-0x59): standard message bit, digits 0-9
    // '0'-'9': standard digit, message bit clear.
    // 'K', 'L', 'Z': ambiguous position placeholder, digit=0, message bit clear.
    // N/S: char 3, letter (msgBit set) = North, digit = South.
    // Lon offset: char 4, letter (msgBit set) = +100 lon degrees.
    // E/W: char 5, letter (msgBit set) = West, digit = East.
    final dest = destination;
    final latDigits = List<int>.filled(6, 0);
    int stdBits = 0;
    int custBits = 0;
    bool isNorth = false;
    bool addLonOffset = false;
    bool isWest = false;

    for (int i = 0; i < 6; i++) {
      final c = dest[i].codeUnitAt(0);
      int digit;
      bool msgBit = false;

      if (c >= 0x30 && c <= 0x39) {
        // '0'-'9': standard digit, message bit clear
        digit = c - 0x30;
        msgBit = false;
      } else if (c >= 0x41 && c <= 0x4A) {
        // 'A'-'J': digits 0-9 with message bit set (custom message)
        digit = c - 0x41;
        msgBit = true;
      } else if (c == 0x4B || c == 0x4C || c == 0x5A) {
        // 'K', 'L', or 'Z': ambiguous position, digit=0, message bit clear
        digit = 0;
        msgBit = false;
      } else if (c >= 0x50 && c <= 0x59) {
        // 'P'-'Y': digits 0-9 with message bit set (standard message)
        digit = c - 0x50;
        msgBit = true;
      } else {
        // Space or other
        digit = 0;
        msgBit = false;
      }

      latDigits[i] = digit;
      if (i < 3 && msgBit) {
        if (c >= 0x41 && c <= 0x4A) {
          // A-J → Custom message bit
          custBits |= (1 << (2 - i));
        } else if (c >= 0x50 && c <= 0x59) {
          // P-Y → Standard message bit
          stdBits |= (1 << (2 - i));
        }
      }

      // Flag bits from specific positions.
      if (i == 3) isNorth = msgBit; // letter = North
      if (i == 4) addLonOffset = msgBit; // letter = +100 lon degrees
      if (i == 5) isWest = msgBit; // letter = West
    }

    // Latitude: DD MM.HH (BCD from 6 digits)
    final latDeg = latDigits[0] * 10 + latDigits[1];
    final latMin = latDigits[2] * 10 + latDigits[3];
    final latHundredths = latDigits[4] * 10 + latDigits[5];
    final latAbs = latDeg + (latMin + latHundredths / 100.0) / 60.0;
    final lat = isNorth ? latAbs : -latAbs;

    // Info field: DTI(1) + lon(3 bytes) + speed/course(2 bytes) + symCode(1) +
    //             symTable(1) + remainder
    // Bytes are raw ASCII with offsets per spec.
    //
    // Longitude: info[1] - 28 (then +100 if addLonOffset), degrees offset math.
    // Speed: info[4] (hundreds+tens) and info[5] (units) with offsets.
    // Course: info[5] (remainder from speed) and info[6] with offsets.

    final b1 = info.codeUnitAt(1) - 28;
    final b2 = info.codeUnitAt(2) - 28;
    final b3 = info.codeUnitAt(3) - 28;
    final b4 = info.codeUnitAt(4) - 28;
    final b5 = info.codeUnitAt(5) - 28;
    final b6 = info.codeUnitAt(6) - 28;

    // Longitude degrees
    int lonDeg = b1 + (addLonOffset ? 100 : 0);
    // Correct per spec ambiguities
    if (lonDeg >= 180 && lonDeg <= 189) lonDeg -= 80;
    if (lonDeg >= 190 && lonDeg <= 199) lonDeg -= 190;

    // Longitude minutes
    int lonMin = b2;
    if (lonMin >= 60) lonMin -= 60;

    // Longitude hundredths of minutes
    final lonHundredths = b3;

    final lonAbs = lonDeg + (lonMin + lonHundredths / 100.0) / 60.0;
    final lon = isWest ? -lonAbs : lonAbs;

    // Speed: sp = b4 * 10 + b5 / 10
    final speedHundreds = b4 * 10;
    final speedUnits = b5 ~/ 10;
    int speedKnots = speedHundreds + speedUnits;
    if (speedKnots >= 800) speedKnots -= 800;

    // Course: dc = (b5 % 10) * 100 + b6
    int course = (b5 % 10) * 100 + b6;
    if (course >= 400) course -= 400;

    // Symbol
    final symbolCode = info.length > 7 ? info[7] : '>';
    final symbolTable = info.length > 8 ? info[8] : '/';

    // Comment (everything after the 9 fixed bytes).
    var comment = info.length > 9 ? info.substring(9) : '';

    // Strip telemetry prefix / device-type prefix from the Mic-E comment.
    //
    // APRS 1.0.1 ch.10 p.54 defines two telemetry flag bytes:
    //   0x60 (`) = 2-channel telemetry: 1 flag byte + 4 hex chars (two 8-bit
    //              channels encoded as 4 hex digits) = 5 bytes total to strip.
    //   0x27 (') = 5-channel telemetry: 1 flag byte + 10 hex chars (five 8-bit
    //              channels encoded as 10 hex digits) = 11 bytes total to strip.
    //
    // Crucially, the hex digits that follow MUST be [0-9a-fA-F]. When they are
    // not (e.g. the FT3DR uses backtick as a 1-byte device-type prefix followed
    // by plain user text), only the flag byte itself is stripped.
    //
    // This matches the behaviour of aprslib (regex '^(`[0-9a-f]{4}|\'[0-9a-f]{10})')
    // and Dire Wolf's deviceid_decode_mice(), which all other popular APRS
    // clients follow — they never cut characters from a user comment.
    if (comment.isNotEmpty &&
        (comment.codeUnitAt(0) == 0x60 || comment.codeUnitAt(0) == 0x27)) {
      final isBacktick = comment.codeUnitAt(0) == 0x60;
      final hexCount = isBacktick ? 4 : 10;
      if (comment.length > hexCount &&
          comment
              .substring(1, hexCount + 1)
              .split('')
              .every(
                (c) =>
                    (c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39) ||
                    (c.codeUnitAt(0) >= 0x41 && c.codeUnitAt(0) <= 0x46) ||
                    (c.codeUnitAt(0) >= 0x61 && c.codeUnitAt(0) <= 0x66),
              )) {
        // Valid telemetry block — strip flag + hex digits.
        comment = comment.substring(hexCount + 1);
      } else {
        // Not valid hex telemetry — backtick/apostrophe is a device-type prefix.
        // Strip only 1 byte.
        comment = comment.substring(1);
      }
    }
    // Trim leading whitespace after prefix removal.
    comment = comment.trimLeft();

    // Base-91 altitude in Mic-E comment (APRS 1.0.1 ch.10 p.55):
    // Three base-91 chars [!-{] followed by '}' encode altitude.
    // altitude_feet = (c1-33)*91² + (c2-33)*91 + (c3-33) - 10000
    // Checked before Yaesu block stripping because both start with 0x22.
    double? micEAltitude;
    if (comment.length >= 4) {
      final c1 = comment.codeUnitAt(0);
      final c2 = comment.codeUnitAt(1);
      final c3 = comment.codeUnitAt(2);
      final c4 = comment.codeUnitAt(3);
      if (c1 >= 0x21 &&
          c1 <= 0x7B &&
          c2 >= 0x21 &&
          c2 <= 0x7B &&
          c3 >= 0x21 &&
          c3 <= 0x7B &&
          c4 == 0x7D) {
        // 0x7D = '}'
        micEAltitude =
            ((c1 - 33) * 91 * 91 + (c2 - 33) * 91 + (c3 - 33) - 10000)
                .toDouble();
        comment = comment.substring(4);
      }
    }

    // Yaesu proprietary block: starts with 0x22 (") and is terminated by
    // the first '}' character.  Only reached if the altitude check above did
    // not consume a 4-char block ending in '}'.
    if (comment.isNotEmpty && comment.codeUnitAt(0) == 0x22) {
      final closeIdx = comment.indexOf('}');
      if (closeIdx >= 0) {
        comment = comment.substring(closeIdx + 1);
      } else if (comment.length >= 3) {
        comment = comment.substring(3);
      } else {
        comment = '';
      }
    }

    // Trim both ends before suffix detection so that a trailing space in the
    // info field (common on Yaesu radios) doesn't prevent `_\d$` from matching.
    comment = comment.trim();

    // Resolve device from comment suffix before stripping the suffix.
    final device = DeviceResolver.resolve(micECommentSuffix: comment);

    // Strip device-indicator suffixes from the comment.
    if (comment.endsWith(']=')) {
      comment = comment.substring(0, comment.length - 2);
    } else if (comment.endsWith(']\x22')) {
      comment = comment.substring(0, comment.length - 2);
    } else if (comment.endsWith(']') ||
        comment.endsWith('^') ||
        comment.endsWith('~')) {
      comment = comment.substring(0, comment.length - 1);
    } else if (_micEFt3dRe.hasMatch(comment)) {
      // Strip trailing _\d
      comment = comment.substring(0, comment.length - 2);
    } else {
      // Check for generic > suffix: strip from last > onward if valid.
      final gtIdx = comment.lastIndexOf('>');
      if (gtIdx >= 0 && gtIdx < comment.length - 1) {
        final suffix = comment.substring(gtIdx + 1);
        if (_micEGenericSuffixRe.hasMatch(suffix)) {
          comment = comment.substring(0, gtIdx);
        }
      }
    }
    // Mic-E message from the 3 message bits.
    // Bits 2-0: A B C where A is most significant.
    // stdBits accumulate P-Y chars, custBits accumulate A-J chars.
    final String micEMsg;
    if (stdBits == 0 && custBits == 0) {
      micEMsg = 'Emergency';
    } else if (stdBits > 0 && custBits > 0) {
      micEMsg = 'Unknown';
    } else if (stdBits > 0) {
      micEMsg = _micEMessages[stdBits];
    } else {
      micEMsg = _micECustomMessages[custBits];
    }

    return MicEPacket(
      rawLine: rawLine,
      source: source,
      destination: destination,
      path: path,
      receivedAt: receivedAt,
      transportSource: transportSource,
      lat: lat,
      lon: lon,
      altitude: micEAltitude,
      course: course == 0 ? null : course,
      speed: speedKnots.toDouble(),
      symbolTable: symbolTable,
      symbolCode: symbolCode,
      comment: comment.trim(),
      micEMessage: micEMsg,
      device: device,
    );
  }

  // Regexes reused in Mic-E comment suffix stripping (mirrors DeviceResolver).
  static final _micEFt3dRe = RegExp(r'_\d$');
  // Alphanumeric only — prevents false positives on user comments containing '>'.
  static final _micEGenericSuffixRe = RegExp(r'^[A-Za-z0-9]{2,10}$');

  // ---------------------------------------------------------------------------
  // Timestamp helpers
  // ---------------------------------------------------------------------------

  /// Parse a 7-char APRS timestamp string.
  ///
  /// Supported formats:
  ///   DDHHMMz — day/hour/minute UTC
  ///   DDHMM/  — day/hour/minute local (local variant, per Dire Wolf)
  ///   HHMMSSh — hour/minute/second (local, treated as UTC)
  ///
  /// Returns null if the string does not match any known format.
  DateTime? _parseTimestamp(String ts, DateTime reference) {
    if (ts.length != 7) return null;
    final suffix = ts[6];

    if (suffix == 'z' || suffix == '/') {
      // DDHHMMz (UTC) or DDHMM/ (local variant, Dire Wolf)
      final m = _dhmRe.firstMatch(ts);
      if (m != null) {
        final day = int.tryParse(m.group(1)!);
        final hour = int.tryParse(m.group(2)!);
        final minute = int.tryParse(m.group(3)!);
        if (day != null && hour != null && minute != null) {
          // Construct a DateTime using reference year/month; handle day rollover.
          return DateTime.utc(
            reference.year,
            reference.month,
            day,
            hour,
            minute,
          );
        }
      }
    }

    if (suffix == 'h') {
      // HHMMSSh — hour/minute/second (local time, treated as UTC for simplicity)
      final m = _hmsRe.firstMatch(ts);
      if (m != null) {
        final hour = int.tryParse(m.group(1)!);
        final minute = int.tryParse(m.group(2)!);
        final second = int.tryParse(m.group(3)!);
        if (hour != null && minute != null && second != null) {
          return DateTime.utc(
            reference.year,
            reference.month,
            reference.day,
            hour,
            minute,
            second,
          );
        }
      }
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Coordinate helpers
  // ---------------------------------------------------------------------------

  /// Convert DDMM.HH string to decimal degrees.
  double _ddmm(String s, {required bool isLat}) {
    final d = isLat ? 2 : 3;
    return double.parse(s.substring(0, d)) +
        double.parse(s.substring(d)) / 60.0;
  }

  // ---------------------------------------------------------------------------
  // Unknown packet factory
  // ---------------------------------------------------------------------------

  UnknownPacket _unknown(
    String rawLine,
    String source,
    String destination,
    List<String> path,
    String reason, {
    String rawInfo = '',
    PacketSource transportSource = PacketSource.aprsIs,
  }) {
    return UnknownPacket(
      rawLine: rawLine,
      source: source,
      destination: destination,
      path: path,
      receivedAt: DateTime.now().toUtc(),
      transportSource: transportSource,
      reason: reason,
      rawInfo: rawInfo,
    );
  }
}
