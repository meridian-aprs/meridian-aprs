import 'credential_key.dart';

/// Thrown by [SecureCredentialStore] when the underlying platform store fails.
///
/// Callers should treat this as recoverable: log it and fall back (e.g. prompt
/// the user to re-enter the credential). Missing credentials are NOT modeled
/// as exceptions — [SecureCredentialStore.read] returns `null` for an unknown
/// key. This type is reserved for platform-level failures such as a locked
/// Keychain or a missing `libsecret` on Linux.
class CredentialStoreException implements Exception {
  CredentialStoreException(this.message, {this.cause, this.key});

  /// Human-readable description of what went wrong.
  final String message;

  /// The underlying error (typically a `PlatformException`), if any.
  final Object? cause;

  /// The credential being accessed when the failure occurred, if applicable.
  /// `null` for whole-store operations such as [SecureCredentialStore.clear].
  final CredentialKey? key;

  @override
  String toString() {
    final buffer = StringBuffer('CredentialStoreException: $message');
    if (key != null) buffer.write(' (key: ${key!.name})');
    if (cause != null) buffer.write(' — $cause');
    return buffer.toString();
  }
}
