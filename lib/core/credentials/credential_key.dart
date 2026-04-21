/// Typed identifier for a credential held by [SecureCredentialStore].
///
/// Using an enum (rather than raw strings) means typos at call sites become
/// compile errors, and the full set of credentials the app stores is
/// discoverable in one place.
///
/// To add a new credential:
///   1. Add an enum value below.
///   2. Add a branch to [CredentialKeyStorage.storageKey] returning a stable
///      snake_case string that will be used as the platform storage key.
///   3. Use it at the call site.
///
/// No architectural change — and no existing keys need to move — when new
/// credentials are introduced.
enum CredentialKey {
  /// The APRS-IS passcode for the user's licensed callsign.
  aprsIsPasscode,
}

/// Maps each [CredentialKey] to its on-disk storage key.
///
/// The returned string is what gets passed to the underlying platform store
/// (Keychain item name, EncryptedSharedPreferences key, etc.). These strings
/// are part of the on-device storage contract — do not rename without a
/// migration path.
extension CredentialKeyStorage on CredentialKey {
  String get storageKey {
    switch (this) {
      case CredentialKey.aprsIsPasscode:
        return 'aprs_is_passcode';
    }
  }
}
