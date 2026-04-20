// Tool: update_deviceid.dart
// Refreshes the bundled APRS device-ID snapshot from the APRS Foundation.
//
// Usage (run from project root):
//   dart run tool/update_deviceid.dart
//
// Exits 0 on success, 1 on any failure.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const String _sourceUrl =
    'https://aprs-deviceid.aprsfoundation.org/tocalls.dense.json';
const String _jsonAsset = 'assets/aprs-deviceid/tocalls.dense.json';
const String _dateAsset = 'assets/aprs-deviceid/last_updated.txt';

/// Prefix of the mandatory tocall entry used as a sanity-check sentinel.
/// The database stores this as 'APDR??' (wildcard), so we match by prefix.
const String _sentinelPrefix = 'APDR';

void main() async {
  // --- 1. Fetch ---
  final http.Response response;
  try {
    response = await http.get(Uri.parse(_sourceUrl));
  } catch (e) {
    stderr.writeln('ERROR: HTTP request failed: $e');
    exit(1);
  }

  if (response.statusCode != 200) {
    stderr.writeln(
      'ERROR: Unexpected HTTP status ${response.statusCode} from $_sourceUrl',
    );
    exit(1);
  }

  final String rawBody = response.body;

  // --- 2. Parse + validate ---
  final Object? parsed;
  try {
    parsed = jsonDecode(rawBody);
  } catch (e) {
    stderr.writeln('ERROR: Response is not valid JSON: $e');
    exit(1);
  }

  if (parsed is! Map<String, dynamic>) {
    stderr.writeln('ERROR: JSON root is not an object.');
    exit(1);
  }

  final Map<String, dynamic> root = parsed;

  if (!root.containsKey('tocalls')) {
    stderr.writeln("ERROR: Parsed JSON has no 'tocalls' key.");
    exit(1);
  }

  final Object? tocallsValue = root['tocalls'];
  if (tocallsValue is! Map<String, dynamic>) {
    stderr.writeln("ERROR: 'tocalls' value is not an object.");
    exit(1);
  }

  final Map<String, dynamic> tocalls = tocallsValue;

  // The database stores APRS+Droid as 'APDR??' (wildcard suffix), so check
  // by prefix rather than exact key.
  final bool hasSentinel = tocalls.keys.any(
    (k) => k.startsWith(_sentinelPrefix),
  );
  if (!hasSentinel) {
    stderr.writeln(
      "ERROR: Sanity check failed — no '$_sentinelPrefix*' entry in tocalls.",
    );
    exit(1);
  }

  // --- 3. Write JSON (raw bytes, preserving upstream formatting) ---
  final File jsonFile = File(_jsonAsset);
  try {
    await jsonFile.writeAsString(rawBody);
  } catch (e) {
    stderr.writeln('ERROR: Failed to write $_jsonAsset: $e');
    exit(1);
  }

  // --- 4. Write datestamp ---
  final String today = DateTime.now().toIso8601String().split('T').first;
  final File dateFile = File(_dateAsset);
  try {
    await dateFile.writeAsString('$today\n');
  } catch (e) {
    stderr.writeln('ERROR: Failed to write $_dateAsset: $e');
    exit(1);
  }

  // --- 5. Report ---
  final int count = tocalls.length;
  // ignore: avoid_print — intentional CLI output for this tool script.
  print('Updated: $count tocall entries, dated $today');

  exit(0);
}
