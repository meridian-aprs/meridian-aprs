import 'package:meridian_aprs/core/credentials/credential_key.dart';
import 'package:meridian_aprs/core/credentials/secure_credential_store.dart';

/// In-memory [SecureCredentialStore] used in tests.
///
/// Mirrors the library's natural behaviour: missing keys return null from
/// [read] and no platform errors are simulated. Shared across the tests that
/// construct a [StationSettingsService] or [AprsIsConnection] without needing
/// to mock a real keychain.
class FakeSecureCredentialStore implements SecureCredentialStore {
  final Map<CredentialKey, String> _values = {};

  @override
  Future<String?> read(CredentialKey key) async => _values[key];

  @override
  Future<void> write(CredentialKey key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(CredentialKey key) async {
    _values.remove(key);
  }

  @override
  Future<bool> exists(CredentialKey key) async => _values.containsKey(key);

  @override
  Future<void> clear() async => _values.clear();
}
