/// Integration tests for onboarding persistence via [StationSettingsService].
///
/// Verifies that all fields default correctly, round-trip through
/// SharedPreferences, and that the 36-character comment cap is enforced.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meridian_aprs/services/station_settings_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ---------------------------------------------------------------------------
  // 1. Default values on fresh install
  // ---------------------------------------------------------------------------

  test('all fields default correctly on fresh install', () async {
    final prefs = await SharedPreferences.getInstance();
    final service = StationSettingsService(prefs);

    expect(service.callsign, '');
    expect(service.ssid, 0);
    expect(service.symbolTable, '/');
    expect(service.symbolCode, '>');
    expect(service.comment, '');
    expect(service.isLicensed, false);
    expect(service.passcode, '');
  });

  // ---------------------------------------------------------------------------
  // 2. Callsign + SSID round-trip (simulates cold restart)
  // ---------------------------------------------------------------------------

  test('callsign and SSID round-trip across service instances', () async {
    final prefs = await SharedPreferences.getInstance();
    final service1 = StationSettingsService(prefs);

    await service1.setCallsign('W1AW');
    await service1.setSsid(9);

    // Simulate cold restart: new instance reads the same prefs singleton.
    final service2 = StationSettingsService(prefs);

    expect(service2.callsign, 'W1AW');
    expect(service2.ssid, 9);
  });

  // ---------------------------------------------------------------------------
  // 3. isLicensed round-trip
  // ---------------------------------------------------------------------------

  test('isLicensed round-trips across service instances', () async {
    final prefs = await SharedPreferences.getInstance();
    final service1 = StationSettingsService(prefs);

    await service1.setIsLicensed(true);

    final service2 = StationSettingsService(prefs);
    expect(service2.isLicensed, true);
  });

  // ---------------------------------------------------------------------------
  // 4. passcode round-trip
  // ---------------------------------------------------------------------------

  test('passcode round-trips across service instances', () async {
    final prefs = await SharedPreferences.getInstance();
    final service1 = StationSettingsService(prefs);

    await service1.setPasscode('12345');

    final service2 = StationSettingsService(prefs);
    expect(service2.passcode, '12345');
  });

  // ---------------------------------------------------------------------------
  // 5. setComment caps at 36 characters
  // ---------------------------------------------------------------------------

  test('setComment truncates input to 36 characters', () async {
    final prefs = await SharedPreferences.getInstance();
    final service = StationSettingsService(prefs);

    // Pass a 50-character string — should be capped at 36.
    const input = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789ABCDEF'; // 42 chars
    await service.setComment(input);

    expect(service.comment.length, 36);
    expect(service.comment, input.substring(0, 36));

    // Verify the truncated value also persisted.
    final service2 = StationSettingsService(prefs);
    expect(service2.comment.length, 36);
  });
}
