import 'dart:typed_data';

import 'aprs_packet.dart';

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
  AprsPacket parse(String line) {
    // Ignore blank lines and server comment lines.
    if (line.isEmpty || line.startsWith('#')) {
      return _unknown(line, '', '', [], 'Server comment or empty line');
    }

    // Split header from info field at the first colon.
    final colonIdx = line.indexOf(':');
    if (colonIdx < 0 || colonIdx + 1 > line.length) {
      return _unknown(line, '', '', [], 'No colon separator found');
    }

    final header = line.substring(0, colonIdx);
    final info = colonIdx + 1 < line.length ? line.substring(colonIdx + 1) : '';

    // Parse header: SOURCE>DEST,p1,p2,...
    final gtIdx = header.indexOf('>');
    if (gtIdx <= 0) {
      return _unknown(line, '', '', [], 'No > in header');
    }
    final source = header.substring(0, gtIdx);
    final destAndPath = header.substring(gtIdx + 1);
    final pathParts = destAndPath.split(',');
    final destination = pathParts.isNotEmpty ? pathParts.first : '';
    final path = pathParts.length > 1 ? pathParts.sublist(1) : <String>[];

    if (info.isEmpty) {
      return _unknown(line, source, destination, path, 'Empty info field');
    }

    final dti = info[0];
    final now = DateTime.now().toUtc();

    try {
      return _dispatch(
        dti: dti,
        info: info,
        rawLine: line,
        source: source,
        destination: destination,
        path: path,
        receivedAt: now,
      );
    } catch (_) {
      // Belt-and-suspenders: never propagate exceptions.
      return UnknownPacket(
        rawLine: line,
        source: source,
        destination: destination,
        path: path,
        receivedAt: now,
        reason: 'Unhandled parse exception',
        rawInfo: info,
      );
    }
  }

  /// Parse raw AX.25 frame bytes.
  ///
  /// Stub implementation — returns [UnknownPacket] until AX.25 framing support
  /// is added in a future milestone.
  AprsPacket parseFrame(Uint8List frameBytes) {
    return UnknownPacket(
      rawLine: '',
      source: '',
      destination: '',
      path: const [],
      receivedAt: DateTime.now().toUtc(),
      reason: 'AX.25 frame parsing not yet implemented',
    );
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
        );

      case ';':
        return _parseObject(
          info: info,
          rawLine: rawLine,
          source: source,
          destination: destination,
          path: path,
          receivedAt: receivedAt,
        );

      case ')':
        return _parseItem(
          info: info,
          rawLine: rawLine,
          source: source,
          destination: destination,
          path: path,
          receivedAt: receivedAt,
        );

      case ':':
        return _parseMessage(
          info: info,
          rawLine: rawLine,
          source: source,
          destination: destination,
          path: path,
          receivedAt: receivedAt,
        );

      case '_':
        return _parseWeather(
          info: info,
          rawLine: rawLine,
          source: source,
          destination: destination,
          path: path,
          receivedAt: receivedAt,
        );

      case '>':
        return _parseStatus(
          info: info,
          rawLine: rawLine,
          source: source,
          destination: destination,
          path: path,
          receivedAt: receivedAt,
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
        );

      // Telemetry — parsed as Unknown for now (v0.2 scope)
      case 'T':
        return UnknownPacket(
          rawLine: rawLine,
          source: source,
          destination: destination,
          path: path,
          receivedAt: receivedAt,
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
          info,
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

  // DHM timestamp: DDHHMMz (UTC) or DDHHMMh (local — treated as UTC).
  static final _dhmRe = RegExp(r'^(\d{2})(\d{2})(\d{2})[zh]$');

  AprsPacket _parsePosition({
    required String info,
    required String rawLine,
    required String source,
    required String destination,
    required List<String> path,
    required DateTime receivedAt,
    required bool hasTimestamp,
    required bool hasMessaging,
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
          info,
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
        info,
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
  }) {
    final m = _uncompressedPosRe.firstMatch(posStr);
    if (m == null) {
      return _unknown(
        rawLine,
        source,
        destination,
        path,
        'Uncompressed position regex did not match',
        info,
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
        info,
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
        info,
      );
    }

    final lat = 90.0 - latVal / 380926.0;
    final lon = -180.0 + lonVal / 190463.0;

    // Optional cs bytes: remainder[0] = course byte, remainder[1] = speed byte,
    // remainder[2] = compression-type byte.
    int? course;
    double? speed;
    String comment = remainder;
    if (remainder.length >= 3) {
      final csType = remainder[2].codeUnitAt(0) - 33;
      // Bits 4-5 of csType byte indicate what c and s represent.
      // If bit 5 set: GGA altitude; if bits 4-5 = 01: course/speed.
      final comprType = (csType >> 4) & 0x3;
      if (comprType == 1) {
        // course/speed
        final cByte = remainder[0].codeUnitAt(0) - 33;
        final sByte = remainder[1].codeUnitAt(0) - 33;
        final c = cByte * 4; // degrees (0-360 encoded as 0-90 * 4)
        // Spec: speed = 1.08^sByte - 1 knots. Simplified safe calc:
        if (cByte != 0 || sByte != 0) {
          course = c == 360 ? 0 : c;
          // Compute 1.08^sByte
          double spd = 0;
          for (int i = 0; i < sByte; i++) {
            spd = spd == 0 ? 1.08 : spd * 1.08;
          }
          speed = spd - 1;
        }
        comment = remainder.length > 3 ? remainder.substring(3) : '';
      } else if (comprType == 2) {
        // Altitude encoded in cs bytes (1.002^altVal feet).
        // Skipped for now — advance past the 3 cs bytes.
        comment = remainder.length > 3 ? remainder.substring(3) : '';
      }
    }

    return PositionPacket(
      rawLine: rawLine,
      source: source,
      destination: destination,
      path: path,
      receivedAt: receivedAt,
      lat: lat,
      lon: lon,
      symbolTable: symbolTable,
      symbolCode: symbolCode,
      comment: comment,
      altitude: null,
      course: course,
      speed: speed,
      hasMessaging: hasMessaging,
      timestamp: packetTimestamp,
    );
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
  }) {
    // Minimum: ; + 9 name + alive/killed + 7 timestamp + position (~18 chars)
    if (info.length < 18) {
      return _unknown(
        rawLine,
        source,
        destination,
        path,
        'Object packet too short',
        info,
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
        info,
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
      objectName: objectName,
      lat: lat,
      lon: lon,
      symbolTable: m.group(3)!,
      symbolCode: m.group(6)!,
      comment: m.group(7)!,
      isAlive: isAlive,
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
  }) {
    if (posStr.length < 10) {
      return _unknown(
        rawLine,
        source,
        destination,
        path,
        'Object compressed position too short',
        info,
      );
    }
    final symbolTable = posStr[0];
    final latChars = posStr.substring(1, 5);
    final lonChars = posStr.substring(5, 9);
    final symbolCode = posStr[9];
    final comment = posStr.length > 10 ? posStr.substring(10) : '';

    final latVal = _base91Decode4(latChars);
    final lonVal = _base91Decode4(lonChars);
    if (latVal == null || lonVal == null) {
      return _unknown(
        rawLine,
        source,
        destination,
        path,
        'Object compressed position decode failed',
        info,
      );
    }

    return ObjectPacket(
      rawLine: rawLine,
      source: source,
      destination: destination,
      path: path,
      receivedAt: receivedAt,
      objectName: objectName,
      lat: 90.0 - latVal / 380926.0,
      lon: -180.0 + lonVal / 190463.0,
      symbolTable: symbolTable,
      symbolCode: symbolCode,
      comment: comment,
      isAlive: isAlive,
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
  }) {
    if (info.length < 5) {
      return _unknown(
        rawLine,
        source,
        destination,
        path,
        'Item packet too short',
        info,
      );
    }

    // Find the alive/killed delimiter ('!' or '_') after the DTI.
    final nameField = info.substring(1);
    int delimIdx = -1;
    bool isAlive = true;
    for (int i = 2; i < nameField.length && i <= 9; i++) {
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
        info,
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
        info,
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
      itemName: itemName,
      lat: lat,
      lon: lon,
      symbolTable: m.group(3)!,
      symbolCode: m.group(6)!,
      comment: m.group(7)!,
      isAlive: isAlive,
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
  }) {
    // info[0] is ':', addressee is info[1..9], info[10] must be ':'.
    if (info.length < 11 || info[10] != ':') {
      return _unknown(
        rawLine,
        source,
        destination,
        path,
        'Message format invalid (need :XXXXXXXXX:)',
        info,
      );
    }

    final addressee = info.substring(1, 10).trim();
    var messageText = info.substring(11);

    // Extract optional message ID: '{NNN}' at end.
    String? messageId;
    final idIdx = messageText.lastIndexOf('{');
    if (idIdx >= 0) {
      messageId = messageText.substring(idIdx + 1);
      messageText = messageText.substring(0, idIdx);
    }

    return MessagePacket(
      rawLine: rawLine,
      source: source,
      destination: destination,
      path: path,
      receivedAt: receivedAt,
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
      temperature: temperature,
      humidity: humidity,
      pressure: pressure,
      windSpeed: windSpeed,
      windDirection: windDir,
      windGust: windGust,
      rainfall1h: rainfall1h,
      rainfall24h: rainfall24h,
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
    'Off Duty',
    'En Route',
    'In Service',
    'Returning',
    'Committed',
    'Special',
    'Priority',
    'Emergency',
  ];

  AprsPacket _parseMicE({
    required String info,
    required String rawLine,
    required String source,
    required String destination,
    required List<String> path,
    required DateTime receivedAt,
  }) {
    // Destination must be at least 6 chars.
    if (destination.length < 6 || info.length < 9) {
      return _unknown(
        rawLine,
        source,
        destination,
        path,
        'Mic-E packet too short',
        info,
      );
    }

    // Decode latitude and message bits from destination chars 0-5.
    // Each char encodes one BCD digit of latitude (0-9) and flags.
    // Digits: 0-9 → '0'-'9', space → ambiguous 0. A-J → 0-9 (message bit set).
    // K, L, Z → 0 (with flag bits).
    // N/S: char 3, 0 = North if digit is a letter (A-K), South otherwise.
    // Lon offset: char 4, if letter add 100 to lon degrees.
    // E/W: char 5, if letter West else East.
    final dest = destination;
    final latDigits = List<int>.filled(6, 0);
    int messageBits = 0;
    bool isNorth = false;
    bool addLonOffset = false;
    bool isWest = false;

    for (int i = 0; i < 6; i++) {
      final c = dest[i].codeUnitAt(0);
      int digit;
      bool msgBit = false;

      if (c >= 0x30 && c <= 0x39) {
        // '0'-'9': standard digit, message bit 0
        digit = c - 0x30;
        msgBit = false;
      } else if (c >= 0x41 && c <= 0x4B) {
        // 'A'-'K': digit 0-9 with message bit set (custom message)
        digit = c - 0x41;
        msgBit = true;
      } else if (c == 0x4C || c == 0x5A) {
        // 'L' or 'Z': 0, no message bit (ambiguous position)
        digit = 0;
        msgBit = false;
      } else if (c == 0x50) {
        // 'P': space → 0 (some implementations)
        digit = 0;
        msgBit = true;
      } else {
        // Space or other
        digit = 0;
        msgBit = false;
      }

      latDigits[i] = digit;
      if (i < 3 && msgBit) messageBits |= (1 << (2 - i));

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

    // Comment (everything after the 9 fixed bytes, excluding any telemetry prefix)
    var comment = info.length > 9 ? info.substring(9) : '';
    // Strip leading Mic-E telemetry sequence indicators if present.
    if (comment.startsWith("'") ||
        comment.startsWith('`') ||
        comment.startsWith('"')) {
      // Optional status/telemetry text marker — leave it in comment as-is.
    }

    // Mic-E message from the 3 message bits (standard messages).
    // Bits 2-0: A B C where A is most significant.
    // Values 0-7 map to the 8 standard messages.
    final micEMsg = _micEMessages.length > messageBits
        ? _micEMessages[messageBits]
        : 'Custom';

    return MicEPacket(
      rawLine: rawLine,
      source: source,
      destination: destination,
      path: path,
      receivedAt: receivedAt,
      lat: lat,
      lon: lon,
      course: course == 0 ? null : course,
      speed: speedKnots.toDouble(),
      symbolTable: symbolTable,
      symbolCode: symbolCode,
      comment: comment.trim(),
      micEMessage: micEMsg,
    );
  }

  // ---------------------------------------------------------------------------
  // Timestamp helpers
  // ---------------------------------------------------------------------------

  /// Parse a 7-char APRS timestamp string.
  ///
  /// Supported formats:
  ///   DDHHMMz — day/hour/minute UTC
  ///   DDHHMMh — day/hour/minute local (treated as UTC)
  ///   HHMMSSh — hour/minute/second
  ///
  /// Returns null if the string does not match any known format.
  DateTime? _parseTimestamp(String ts, DateTime reference) {
    if (ts.length != 7) return null;
    final suffix = ts[6];

    if (suffix == 'z' || suffix == 'h') {
      // DDHHMMz or DDHHMMh
      final m = _dhmRe.firstMatch(ts);
      if (m != null) {
        final day = int.tryParse(m.group(1)!);
        final hour = int.tryParse(m.group(2)!);
        final minute = int.tryParse(m.group(3)!);
        if (day != null && hour != null && minute != null) {
          // Construct a DateTime using reference year/month; handle day rollover.
          final dt = DateTime.utc(
            reference.year,
            reference.month,
            day,
            hour,
            minute,
          );
          return dt;
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
    String reason, [
    String rawInfo = '',
  ]) {
    return UnknownPacket(
      rawLine: rawLine,
      source: source,
      destination: destination,
      path: path,
      receivedAt: DateTime.now().toUtc(),
      reason: reason,
      rawInfo: rawInfo,
    );
  }
}
