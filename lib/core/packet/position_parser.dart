import 'result.dart';
import 'station.dart';

// Top-level function — tested directly by ax25_parser_test.dart
ParseResult<Station> parseAprsLine(String raw) {
  if (raw.isEmpty || raw.startsWith('#')) return Err('Not a data line');

  final colonIdx = raw.indexOf(':');
  if (colonIdx < 0 || colonIdx + 1 >= raw.length) return Err('No info field');

  final header = raw.substring(0, colonIdx);
  final info = raw.substring(colonIdx + 1);

  final gtIdx = header.indexOf('>');
  if (gtIdx <= 0) return Err('No callsign');
  final callsign = header.substring(0, gtIdx);

  if (info.isEmpty) return Err('Empty info field');
  final dti = info[0];

  // Determine position substring based on DTI:
  //   !  =  → position starts immediately after DTI
  //   /  @  → 7-char timestamp precedes position (DDHHMMz / HHMMSSh)
  final String posStr;
  if (dti == '!' || dti == '=') {
    posStr = info.substring(1);
  } else if (dti == '/' || dti == '@') {
    if (info.length < 9) return Err('Timestamped packet too short');
    posStr = info.substring(8); // skip DTI + 7-char timestamp
  } else {
    return Err('Not a position report (DTI: $dti)');
  }

  final pos = _parsePosition(posStr);
  if (pos == null) return Err('Could not parse position');

  return Ok(
    Station(
      callsign: callsign,
      lat: pos.$1,
      lon: pos.$2,
      rawPacket: raw,
      lastHeard: DateTime.now(),
      symbolTable: pos.$3,
      symbolCode: pos.$4,
      comment: pos.$5,
    ),
  );
}

// Plain (uncompressed) APRS position: DDmm.mmN<symTable>DDDmm.mmW<symCode><comment>
// Groups: (lat digits)(N|S)(symbolTable)(lon digits)(E|W)(symbolCode)(comment)
final _posRe = RegExp(r'^(\d{4}\.\d{2})(N|S)(.)(\d{5}\.\d{2})(E|W)(.)(.*)$');

(double, double, String, String, String)? _parsePosition(String s) {
  final m = _posRe.firstMatch(s);
  if (m == null) return null;
  final lat = _ddmm(m.group(1)!, isLat: true) * (m.group(2) == 'S' ? -1 : 1);
  final lon = _ddmm(m.group(4)!, isLat: false) * (m.group(5) == 'W' ? -1 : 1);
  final symbolTable = m.group(3)!;
  final symbolCode = m.group(6)!;
  final comment = m.group(7)!;
  return (lat, lon, symbolTable, symbolCode, comment);
}

double _ddmm(String s, {required bool isLat}) {
  final d = isLat ? 2 : 3;
  return double.parse(s.substring(0, d)) + double.parse(s.substring(d)) / 60.0;
}
