/// Platform-conditional export for [SerialConnection].
///
/// On desktop platforms (dart.library.io) the real implementation is used;
/// on web the stub is exported which throws [UnsupportedError] on all calls.
library;

export 'serial_connection_stub.dart'
    if (dart.library.io) 'serial_connection_impl.dart';
