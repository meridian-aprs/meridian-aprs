import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'credential_key.dart';
import 'credential_store_exception.dart';

/// Platform-backed secure key/value store for sensitive credentials.
///
/// Implementations persist values to the operating system's native secure
/// storage:
///
///   - iOS / macOS: Keychain
///   - Android: Keystore-backed `EncryptedSharedPreferences`
///   - Windows: Credential Manager
///   - Linux: `libsecret` (gnome-keyring / KWallet via libsecret)
///   - Web: encrypted IndexedDB (AES-GCM, standard browser-tier)
///
/// Missing credentials return `null` from [read], never throw. Platform-level
/// failures (locked Keychain, missing libsecret) surface as a typed
/// [CredentialStoreException] the caller can catch, log, and recover from.
abstract class SecureCredentialStore {
  /// Return the stored value for [key], or `null` if no value is stored.
  ///
  /// Throws [CredentialStoreException] only for platform-level failures.
  Future<String?> read(CredentialKey key);

  /// Persist [value] under [key], overwriting any prior value.
  ///
  /// Throws [CredentialStoreException] if the platform store rejects the
  /// write.
  Future<void> write(CredentialKey key, String value);

  /// Remove any value stored under [key]. No-op if the key is not present.
  ///
  /// Throws [CredentialStoreException] for platform-level failures.
  Future<void> delete(CredentialKey key);

  /// Whether a value is currently stored under [key].
  ///
  /// Throws [CredentialStoreException] for platform-level failures.
  Future<bool> exists(CredentialKey key);

  /// Remove every credential managed by this store.
  ///
  /// Intended for "reset app" / logout flows.
  Future<void> clear();
}

/// Default [SecureCredentialStore] implementation backed by
/// `package:flutter_secure_storage`.
class FlutterSecureCredentialStore implements SecureCredentialStore {
  /// Construct a store, optionally injecting a pre-configured
  /// [FlutterSecureStorage] (useful for tests or for callers that want to
  /// override platform options).
  ///
  /// When no storage is supplied, a default is constructed with Android
  /// [EncryptedSharedPreferences] enabled. iOS/macOS use the library's default
  /// Keychain options (`first_unlock` accessibility), which is appropriate for
  /// credentials needed after the user has unlocked the device at least once.
  FlutterSecureCredentialStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(CredentialKey key) async {
    try {
      return await _storage.read(key: key.storageKey);
    } on PlatformException catch (e, st) {
      throw _translate(e, st, 'read', key: key);
    }
  }

  @override
  Future<void> write(CredentialKey key, String value) async {
    try {
      await _storage.write(key: key.storageKey, value: value);
    } on PlatformException catch (e, st) {
      throw _translate(e, st, 'write', key: key);
    }
  }

  @override
  Future<void> delete(CredentialKey key) async {
    try {
      await _storage.delete(key: key.storageKey);
    } on PlatformException catch (e, st) {
      throw _translate(e, st, 'delete', key: key);
    }
  }

  @override
  Future<bool> exists(CredentialKey key) async {
    try {
      return await _storage.containsKey(key: key.storageKey);
    } on PlatformException catch (e, st) {
      throw _translate(e, st, 'exists', key: key);
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.deleteAll();
    } on PlatformException catch (e, st) {
      throw _translate(e, st, 'clear');
    }
  }

  // ---------------------------------------------------------------------------
  // Error translation
  // ---------------------------------------------------------------------------

  CredentialStoreException _translate(
    PlatformException e,
    StackTrace st,
    String op, {
    CredentialKey? key,
  }) {
    final message = _messageFor(e, op);
    debugPrint(
      'SecureCredentialStore: $op failed '
      '(code=${e.code}, message=${e.message}) — $message',
    );
    debugPrintStack(stackTrace: st, label: 'SecureCredentialStore');
    return CredentialStoreException(message, cause: e, key: key);
  }

  String _messageFor(PlatformException e, String op) {
    if (_looksLikeMissingLibsecret(e)) {
      return 'libsecret / gnome-keyring is required for credential storage '
          'on Linux. Install the `libsecret-1-0` (Debian/Ubuntu) or '
          '`libsecret` (Fedora/Arch) package and ensure a secret service '
          'such as gnome-keyring or KWallet is running.';
    }
    return 'Secure credential store $op failed: '
        '${e.message ?? e.code}';
  }

  /// Best-effort detection of "libsecret not installed" on Linux.
  ///
  /// The Linux backend of `flutter_secure_storage` surfaces these as a
  /// `PlatformException` whose message mentions `libsecret` or
  /// `secret service`. We match loosely on either token; false positives only
  /// affect the wording of the error message, not behaviour.
  bool _looksLikeMissingLibsecret(PlatformException e) {
    final haystack = '${e.code} ${e.message ?? ''}'.toLowerCase();
    return haystack.contains('libsecret') ||
        haystack.contains('secret service') ||
        haystack.contains('secret-service');
  }
}
