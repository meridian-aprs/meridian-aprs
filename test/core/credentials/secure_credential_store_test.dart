import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_aprs/core/credentials/credential_key.dart';
import 'package:meridian_aprs/core/credentials/secure_credential_store.dart';

// ---------------------------------------------------------------------------
// In-memory fake used by the contract tests.
//
// Lives in the test file (per Phase 1 scope) rather than in production code.
// Models the library's natural behaviour: missing keys return null from read,
// no platform errors are simulated here.
// ---------------------------------------------------------------------------

class _FakeSecureCredentialStore implements SecureCredentialStore {
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

/// Contract tests — invoked against any [SecureCredentialStore] factory.
///
/// Phase 1 only exercises the [_FakeSecureCredentialStore]. Phase 2+ may
/// reuse this helper against a platform-channel-mocked
/// [FlutterSecureCredentialStore].
void runContractTests(String name, SecureCredentialStore Function() factory) {
  group('$name — SecureCredentialStore contract', () {
    late SecureCredentialStore store;

    setUp(() => store = factory());

    test('read returns null for an unwritten key', () async {
      expect(await store.read(CredentialKey.aprsIsPasscode), isNull);
    });

    test('exists returns false for an unwritten key', () async {
      expect(await store.exists(CredentialKey.aprsIsPasscode), isFalse);
    });

    test('write then read round-trips the value', () async {
      await store.write(CredentialKey.aprsIsPasscode, '12345');
      expect(await store.read(CredentialKey.aprsIsPasscode), '12345');
    });

    test('write then exists returns true', () async {
      await store.write(CredentialKey.aprsIsPasscode, '12345');
      expect(await store.exists(CredentialKey.aprsIsPasscode), isTrue);
    });

    test('write overwrites a prior value', () async {
      await store.write(CredentialKey.aprsIsPasscode, 'old');
      await store.write(CredentialKey.aprsIsPasscode, 'new');
      expect(await store.read(CredentialKey.aprsIsPasscode), 'new');
    });

    test('delete removes a value', () async {
      await store.write(CredentialKey.aprsIsPasscode, '12345');
      await store.delete(CredentialKey.aprsIsPasscode);

      expect(await store.read(CredentialKey.aprsIsPasscode), isNull);
      expect(await store.exists(CredentialKey.aprsIsPasscode), isFalse);
    });

    test('delete is a no-op for an unwritten key', () async {
      await store.delete(CredentialKey.aprsIsPasscode);
      expect(await store.read(CredentialKey.aprsIsPasscode), isNull);
    });

    test('clear empties the store', () async {
      await store.write(CredentialKey.aprsIsPasscode, '12345');
      await store.clear();

      expect(await store.read(CredentialKey.aprsIsPasscode), isNull);
      expect(await store.exists(CredentialKey.aprsIsPasscode), isFalse);
    });

    // TODO: add a "multiple keys are independent" test when a second
    // CredentialKey exists. Writing one today would require fabricating a
    // placeholder enum value, which the Phase 1 spec forbids.
  });
}

void main() {
  runContractTests(
    'FakeSecureCredentialStore',
    () => _FakeSecureCredentialStore(),
  );

  group('CredentialKey.storageKey', () {
    test('aprsIsPasscode maps to aprs_is_passcode', () {
      expect(CredentialKey.aprsIsPasscode.storageKey, 'aprs_is_passcode');
    });
  });

  group('FlutterSecureCredentialStore', () {
    test('can be constructed without touching platform channels', () {
      // Construction only captures a `const FlutterSecureStorage` reference
      // and does not invoke any method channel. Exercising actual storage
      // would require a platform-channel mock (Phase 5 manual testing).
      expect(FlutterSecureCredentialStore.new, returnsNormally);
    });
  });
}
